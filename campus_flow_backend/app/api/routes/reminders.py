from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, date, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import enhance_reminder, analyze_stress_density

router = APIRouter()


# ── Constants ──────────────────────────────────────────────────────────────────

WELLNESS_COOLDOWN_MINUTES = {"water": 90, "meal": 180, "sleep": 240, "break": 120}
DEADLINE_FIRE_TIME_TODAY = "09:00"
DEADLINE_FIRE_TIME_TOMORROW = "20:00"


# ── Models ────────────────────────────────────────────────────────────────────

class PreClassReminderRequest(BaseModel):
    user_id: str
    class_info: dict        # {subject, start_time, end_time, room, professor}
    minutes_before: int = 30

class WellnessReminderCheckRequest(BaseModel):
    user_id: str
    reminder_type: str      # "water"|"meal"|"sleep"|"break"
    current_time: str       # HH:MM

class DismissWellnessRequest(BaseModel):
    user_id: str
    reminder_type: str

class StressDensityRequest(BaseModel):
    user_id: str

class BookingReminderRequest(BaseModel):
    user_id: str
    event_id: str           # Schedule item_id of the booking/event
    current_time: str       # HH:MM — current time to calculate when to fire

class SmartReminderBatchRequest(BaseModel):
    """Request to generate all smart reminders for today at once."""
    user_id: str
    current_time: str       # HH:MM


# ── Routes ────────────────────────────────────────────────────────────────────

# ── ENHANCED: Contextual Smart Reminders ──────────────────────────────────────

@router.post("/pre-class")
async def get_pre_class_reminder(req: PreClassReminderRequest):
    """
    ENHANCED contextual smart reminder.
    Not just "class at 9AM". Instead: "Physics at 9AM — Prof's WhatsApp says
    bring your lab notebook today."

    Claude adds message context to every reminder by scanning recent
    academic notifications for mentions of the class subject.
    """
    notif_table = get_table("notifications")
    # Look back further (6 hours) for more context
    cutoff = (datetime.now() - timedelta(hours=6)).isoformat()

    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notifs = response.get("Items", [])

    # Find relevant messages: academic category OR mentions the subject
    subject_lower = req.class_info.get("subject", "").lower()
    prof_name = req.class_info.get("professor", "").lower()

    relevant = [
        n for n in all_notifs
        if n.get("ingested_at", "") >= cutoff
        and (
            n.get("category") == "academic"
            or subject_lower in n.get("body", "").lower()
            or subject_lower in n.get("title", "").lower()
            or subject_lower in n.get("summary", "").lower()
            or (prof_name and prof_name in n.get("title", "").lower())
            or (prof_name and prof_name in n.get("body", "").lower())
        )
    ][:10]

    enhanced_text = enhance_reminder(req.class_info, relevant)

    return {
        "reminder_text": enhanced_text,
        "class": req.class_info,
        "fire_at_minutes_before": req.minutes_before,
        "context_messages_found": len(relevant),
        "context_preview": [
            {"app": n.get("app"), "summary": n.get("summary", n.get("title"))}
            for n in relevant[:3]
        ],
    }


# ── NEW: Smart Reminder Batch ─────────────────────────────────────────────────

@router.post("/smart-batch")
async def get_smart_reminders_batch(req: SmartReminderBatchRequest):
    """
    Generates ALL smart reminders for today in one call.
    Called once when the app opens. Returns a list of timed reminders
    that the Flutter app schedules via flutter_local_notifications.

    Includes:
    - Pre-class reminders (30 min before each class)
    - Booking/event reminders (with travel time)
    - Deadline reminders (if task due today/tomorrow)
    """
    schedule_table = get_table("schedules")
    task_table = get_table("tasks")
    notif_table = get_table("notifications")

    today_day = date.today().strftime("%A")
    today_str = date.today().strftime("%Y-%m-%d")
    tomorrow_str = (date.today() + timedelta(days=1)).strftime("%Y-%m-%d")
    current_time = req.current_time

    # Fetch schedule
    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_items = sched_resp.get("Items", [])

    # Today's classes
    classes_today = [
        c for c in all_items
        if c.get("type") == "class" and c.get("day", "").lower() == today_day.lower()
    ]

    # Today's events (bookings, interviews, etc.)
    events_today = [
        e for e in all_items
        if e.get("type") == "event" and e.get("date") == today_str
    ]

    # Tasks due today or tomorrow
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    deadline_tasks = [
        t for t in task_resp.get("Items", [])
        if t.get("deadline") in [today_str, tomorrow_str]
        and t.get("status") != "done"
    ]

    # Fetch recent notifications for context enrichment
    cutoff_6h = (datetime.now() - timedelta(hours=6)).isoformat()
    notif_resp = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    recent_academic = [
        n for n in notif_resp.get("Items", [])
        if n.get("ingested_at", "") >= cutoff_6h and n.get("category") == "academic"
    ]

    reminders = []

    # 1. Pre-class reminders with context
    for cls in classes_today:
        class_time = cls.get("start_time", "")
        if class_time <= current_time:
            continue    # Skip classes already started or passed

        # Find messages mentioning this subject
        subject_lower = cls.get("subject", "").lower()
        relevant_msgs = [
            n for n in recent_academic
            if subject_lower in n.get("summary", "").lower()
            or subject_lower in n.get("body", "").lower()
        ][:3]

        enhanced = enhance_reminder(cls, relevant_msgs)

        # Calculate reminder fire time (30 min before)
        fire_time = _subtract_minutes(class_time, 30)

        reminders.append({
            "type": "pre_class",
            "fire_at": fire_time,
            "title": f"🎓 {cls.get('subject', 'Class')} in 30 min",
            "body": enhanced,
            "class_info": cls,
            "has_context": len(relevant_msgs) > 0,
        })

    # 2. Booking/event reminders with travel time
    for event in events_today:
        event_time = event.get("start_time", "")
        if event_time <= current_time:
            continue

        travel_time = int(event.get("travel_time_minutes", 0))
        reminder_before = int(event.get("reminder_minutes_before", travel_time + 30))
        fire_time = _subtract_minutes(event_time, reminder_before)

        title_prefix = {
            "travel": "🚂",
            "interview": "💼",
            "entertainment": "🎬",
            "medical": "🏥",
            "meeting": "🤝",
        }.get(event.get("category"), "📅")

        body = f"{event.get('title', 'Event')} at {event_time}"
        if event.get("location"):
            body += f" — {event['location']}"
        if travel_time > 0:
            body += f" (leave by {_subtract_minutes(event_time, travel_time)})"

        reminders.append({
            "type": "booking_event",
            "fire_at": fire_time,
            "title": f"{title_prefix} {event.get('title', 'Event')}",
            "body": body,
            "event_info": event,
            "travel_time_minutes": travel_time,
        })

    # 3. Deadline reminders
    for task in deadline_tasks:
        is_today = task.get("deadline") == today_str
        fire_time = DEADLINE_FIRE_TIME_TODAY if is_today else DEADLINE_FIRE_TIME_TOMORROW

        if fire_time <= current_time and is_today:
            fire_time = current_time  # Fire immediately if past morning

        reminders.append({
            "type": "deadline",
            "fire_at": fire_time,
            "title": f"⏰ {'Due TODAY' if is_today else 'Due tomorrow'}: {task.get('title', 'Task')}",
            "body": f"{task.get('title', 'Task')} — deadline: {task.get('deadline')}",
            "task_info": task,
            "is_today": is_today,
        })

    # Sort all reminders by fire time
    reminders.sort(key=lambda x: x.get("fire_at", "99:99"))

    return {
        "reminders": reminders,
        "total": len(reminders),
        "next_reminder": reminders[0] if reminders else None,
    }


# ── NEW: Booking / Event Reminder ─────────────────────────────────────────────

@router.post("/booking-reminder")
async def get_booking_reminder(req: BookingReminderRequest):
    """
    For a specific booking/event, generates a contextual reminder
    that includes travel time and preparation steps.

    Example: "Interview at TCS in 2 hours — leave by 1:30 PM.
    Don't forget your resume and ID proof."
    """
    schedule_table = get_table("schedules")

    # Fetch the event
    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    event = next(
        (i for i in sched_resp.get("Items", []) if i.get("item_id") == req.event_id),
        None
    )
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    event_time = event.get("start_time", "")
    travel_time = int(event.get("travel_time_minutes", 0))
    category = event.get("category", "other")

    # Calculate departure time
    leave_by = _subtract_minutes(event_time, travel_time) if travel_time > 0 else None

    # Generate category-specific preparation tips
    prep_tips = _get_prep_tips(category)

    body = f"{event.get('title', 'Event')} at {event_time}"
    if event.get("location"):
        body += f" — {event['location']}"
    if leave_by:
        body += f"\nLeave by {leave_by} ({travel_time} min travel time)"
    if event.get("booking_reference"):
        body += f"\nBooking ref: {event['booking_reference']}"

    return {
        "reminder_text": body,
        "event": event,
        "leave_by": leave_by,
        "travel_time_minutes": travel_time,
        "prep_tips": prep_tips,
        "fire_at": _subtract_minutes(event_time, travel_time + 30),
    }


@router.post("/wellness-check")
async def check_wellness_reminder(req: WellnessReminderCheckRequest):
    """
    Before firing a wellness reminder (water/meal/sleep), checks:
    1. Is student currently in class? → skip
    2. Is screen likely off (phone idle)? → skip
    3. Was last reminder dismissed recently? → skip
    Returns: should_fire: bool, reason: str
    """
    schedule_table = get_table("schedules")
    routine_table = get_table("routine_logs")
    wellness_table = get_table("wellness")

    today_day = date.today().strftime("%A")
    current_time = req.current_time

    # Check if in class right now
    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    classes_today = [
        c for c in sched_resp.get("Items", [])
        if c.get("type") == "class" and c.get("day", "").lower() == today_day.lower()
    ]
    in_class = any(
        c.get("start_time", "99:99") <= current_time <= c.get("end_time", "00:00")
        for c in classes_today
    )
    if in_class:
        return {"should_fire": False, "reason": "Student is in class"}

    # Check current activity context — suppress during workout/commute
    ctx_resp = routine_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    contexts = [e for e in ctx_resp.get("Items", []) if e.get("type") == "activity_context"]
    if contexts:
        latest_ctx = max(contexts, key=lambda x: x.get("timestamp", ""))
        if latest_ctx.get("context") in ["workout", "commute", "class"]:
            return {"should_fire": False, "reason": f"Student is {latest_ctx.get('context')}"}

    # Check if reminder was recently dismissed
    cool_down = WELLNESS_COOLDOWN_MINUTES.get(req.reminder_type, 90)
    cutoff = (datetime.now() - timedelta(minutes=cool_down)).isoformat()

    well_resp = wellness_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    recent_dismissals = [
        w for w in well_resp.get("Items", [])
        if w.get("type") == f"dismissed_{req.reminder_type}"
        and w.get("date", "") >= cutoff[:10]
    ]
    if recent_dismissals:
        return {"should_fire": False, "reason": "Recently dismissed"}

    return {"should_fire": True, "reason": "All checks passed"}


@router.post("/dismiss-wellness")
async def dismiss_wellness_reminder(req: DismissWellnessRequest):
    """
    Records that a wellness reminder was dismissed.
    """
    table = get_table("wellness")
    item = {
        "user_id": req.user_id,
        "date": datetime.now().isoformat(),
        "type": f"dismissed_{req.reminder_type}",
        "dismissed_at": datetime.now().isoformat(),
    }
    table.put_item(Item=item)
    return {"recorded": True}


@router.post("/stress-density")
async def get_stress_density(req: StressDensityRequest):
    """
    Calculates the 48-hour load score and returns a wellness message.
    """
    schedule_table = get_table("schedules")
    task_table = get_table("tasks")
    notif_table = get_table("notifications")

    today = date.today().isoformat()
    two_days = (date.today() + timedelta(days=2)).isoformat()
    today_day = date.today().strftime("%A")
    tomorrow_day = (date.today() + timedelta(days=1)).strftime("%A")

    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    schedule_48h = [
        c for c in sched_resp.get("Items", [])
        if c.get("type") == "class"
        and c.get("day", "") in [today_day, tomorrow_day]
    ]

    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    deadlines_48h = [
        t for t in task_resp.get("Items", [])
        if t.get("deadline", "9999") >= today
        and t.get("deadline", "0000") <= two_days
        and t.get("status") != "done"
    ]

    notif_resp = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    cutoff_2h = (datetime.now() - timedelta(hours=2)).isoformat()
    urgent_notifs = [
        n for n in notif_resp.get("Items", [])
        if int(n.get("priority", 1)) >= 4
        and n.get("ingested_at", "") >= cutoff_2h
        and not n.get("is_read", False)
    ]

    result = analyze_stress_density(schedule_48h, deadlines_48h, len(urgent_notifs))
    return result


@router.post("/tasks/{user_id}/confirm/{task_id}")
async def confirm_task(user_id: str, task_id: str):
    """
    User confirms a deadline that was auto-extracted.
    """
    table = get_table("tasks")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    task = next((t for t in response.get("Items", []) if t.get("task_id") == task_id), None)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    table.update_item(
        Key={"user_id": user_id, "task_id": task_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "todo"},
    )
    return {"confirmed": True, "task_id": task_id}


@router.post("/tasks/{user_id}/update-status/{task_id}")
async def update_task_status(user_id: str, task_id: str, status: str):
    """
    Updates task status: pending_confirmation → todo → in_progress → done
    """
    valid_statuses = ["pending_confirmation", "todo", "in_progress", "done"]
    if status not in valid_statuses:
        raise HTTPException(status_code=400, detail=f"Status must be one of {valid_statuses}")

    table = get_table("tasks")
    table.update_item(
        Key={"user_id": user_id, "task_id": task_id},
        UpdateExpression="SET #s = :s, updated_at = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": status, ":t": datetime.now().isoformat()},
    )
    return {"updated": True, "task_id": task_id, "new_status": status}


@router.get("/tasks/{user_id}")
async def get_all_tasks(user_id: str, status: Optional[str] = None):
    """
    Returns all tasks, optionally filtered by status.
    """
    table = get_table("tasks")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    tasks = response.get("Items", [])
    if status:
        tasks = [t for t in tasks if t.get("status") == status]

    tasks.sort(key=lambda x: x.get("deadline", "9999"))
    return {"tasks": tasks, "total": len(tasks)}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _subtract_minutes(time_str: str, minutes: int) -> str:
    """Subtracts N minutes from an HH:MM time string. Returns HH:MM."""
    try:
        h, m = map(int, time_str.split(":"))
        total = h * 60 + m - minutes
        if total < 0:
            total += 24 * 60    # Wrap around midnight
        return f"{(total // 60) % 24:02d}:{total % 60:02d}"
    except (ValueError, IndexError):
        return time_str


def _get_prep_tips(category: str) -> list:
    """Returns category-specific preparation tips for event reminders."""
    tips = {
        "travel": [
            "Check your ticket/PNR status",
            "Pack essentials and charger",
            "Download offline maps for the destination",
        ],
        "interview": [
            "Carry extra copies of your resume",
            "Bring ID proof and any requested documents",
            "Review the company's recent news",
            "Dress formally and arrive 15 min early",
        ],
        "entertainment": [
            "Check your booking confirmation",
            "Charge your phone for tickets",
        ],
        "medical": [
            "Bring any previous reports or prescriptions",
            "Note down symptoms or questions for the doctor",
        ],
        "meeting": [
            "Review the meeting agenda",
            "Prepare any materials discussed in recent messages",
        ],
    }
    return tips.get(category, ["Review any related messages for context"])