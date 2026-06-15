from fastapi import APIRouter, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, date, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import (
    parse_timetable_text,
    generate_exam_checklist,
    suggest_free_slot_tasks,
    detect_booking_events,
    generate_exam_countdown,
)
from app.services.aws_service import extract_text_from_image, upload_to_s3

router = APIRouter()
 
# ── Constants ──────────────────────────────────────────────────────────────────

WORK_START = "08:00"
WORK_END = "22:00"
MIN_SLOT_DURATION = 60

COLOR_MAP = {
    "class": "#E8592B",
    "deadline": "#D32F2F",
    "overdue": "#B71C1C",
    "exam": "#7B1FA2",
    "exam_prep": "#7B1FA2",
    "personal": "#1976D2",
    "travel": "#00796B",
    "interview": "#F57C00",
    "entertainment": "#E91E63",
    "medical": "#388E3C",
    "meeting": "#5D4037",
    "other": "#607D8B",
}

# ── Models ────────────────────────────────────────────────────────────────────

class ClassEntry(BaseModel):
    day: str
    start_time: str
    end_time: str
    subject: str
    room: Optional[str] = None
    professor: Optional[str] = None

class ScheduleResponse(BaseModel):
    user_id: str
    classes: List[ClassEntry]
    parsed_at: str

class ManualEventRequest(BaseModel):
    user_id: str
    title: str
    date: str           # YYYY-MM-DD
    start_time: str     # HH:MM
    end_time: str
    category: str       # class|deadline|exam|personal|travel|interview
    location: Optional[str] = None
    notes: Optional[str] = None
    travel_time_minutes: Optional[int] = None   # For booking/event reminders

class ExamChecklistRequest(BaseModel):
    user_id: str
    exam_subject: str
    exam_date: str      # YYYY-MM-DD

class FreeSlotSuggestionRequest(BaseModel):
    user_id: str
    target_date: Optional[str] = None   # YYYY-MM-DD, defaults to today

class ExamCountdownRequest(BaseModel):
    user_id: str
    exam_subject: str
    exam_date: str      # YYYY-MM-DD
    exam_time: Optional[str] = None     # HH:MM

class DetectBookingsRequest(BaseModel):
    user_id: str
    hours_back: int = 48    # Scan last N hours of notifications


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/upload-image")
async def upload_timetable_image(user_id: str, file: UploadFile = File(...)):
    """
    Step 1: Upload timetable photo.
    Step 2: Rekognition OCR extracts text.
    Step 3: Claude parses into structured JSON.
    Step 4: Save to DynamoDB.
    """
    # Accept common image content types. Android image_picker often sends
    # application/octet-stream, so we also check file extension as fallback.
    allowed_types = {"image/jpeg", "image/png", "image/jpg", "image/webp",
                     "application/octet-stream"}
    fname = (file.filename or "").lower()
    has_image_ext = fname.endswith((".jpg", ".jpeg", ".png", ".webp"))
    if file.content_type not in allowed_types and not has_image_ext:
        raise HTTPException(status_code=400, detail=f"Only images accepted. Got: {file.content_type}")

    image_bytes = await file.read()

    # OCR via Rekognition
    ocr_text = extract_text_from_image(image_bytes)
    if not ocr_text.strip():
        raise HTTPException(status_code=422, detail="No text detected in image. Try a clearer photo.")

    # Upload original to S3 for reference
    s3_key = upload_to_s3(image_bytes, file.filename or "timetable.jpg")

    # Claude parses OCR text into structured schedule
    parsed = parse_timetable_text(ocr_text)

    # Save each class as a separate DynamoDB item
    table = get_table("schedules")
    now = datetime.now().isoformat()
    saved_classes = []

    for cls in parsed.get("classes", []):
        item_id = f"class_{uuid.uuid4().hex[:8]}"
        item = {
            "user_id": user_id,
            "item_id": item_id,
            "type": "class",
            "day": cls.get("day"),
            "start_time": cls.get("start_time"),
            "end_time": cls.get("end_time"),
            "subject": cls.get("subject"),
            "room": cls.get("room"),
            "professor": cls.get("professor"),
            "s3_source": s3_key,
            "created_at": now,
        }
        table.put_item(Item=item)
        saved_classes.append(item)

    return {
        "success": True,
        "ocr_text_preview": ocr_text[:300],
        "classes_parsed": len(saved_classes),
        "classes": saved_classes,
    }


@router.get("/classes/{user_id}")
async def get_schedule(user_id: str):
    """
    Returns all classes for a user.
    """
    table = get_table("schedules")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    items = response.get("Items", [])
    classes = [i for i in items if i.get("type") == "class"]
    events = [i for i in items if i.get("type") == "event"]
    return {"classes": classes, "events": events, "total": len(items)}


@router.post("/event")
async def add_manual_event(req: ManualEventRequest):
    """
    Adds a manual event (exam, interview, booking, etc.)
    """
    table = get_table("schedules")
    item_id = f"event_{uuid.uuid4().hex[:8]}"
    item = {
        "user_id": req.user_id,
        "item_id": item_id,
        "type": "event",
        "title": req.title,
        "date": req.date,
        "start_time": req.start_time,
        "end_time": req.end_time,
        "category": req.category,
        "location": req.location,
        "notes": req.notes,
        "travel_time_minutes": req.travel_time_minutes,
        "created_at": datetime.now().isoformat(),
    }
    table.put_item(Item=item)
    return {"success": True, "event": item}


# ── ENHANCED: Unified Today View ──────────────────────────────────────────────

@router.get("/today/{user_id}")
async def get_today_view(user_id: str):
    """
    UNIFIED today view combining:
    - Class schedule (from timetable)
    - Deadlines extracted from chats/notifications
    - Personal events (manually added)
    - Auto-detected bookings (trains, interviews, etc.)
    
    Color-coded by category. Shows free slots clearly.
    This is the single screen the student opens every morning.
    """
    today = date.today()
    today_str = today.strftime("%Y-%m-%d")
    today_day = today.strftime("%A")

    schedule_table = get_table("schedules")
    task_table = get_table("tasks")
    notif_table = get_table("notifications")

    # Get all schedule items
    schedule_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    all_items = schedule_resp.get("Items", [])

    # Today's classes
    todays_classes = [
        {**i, "color_category": "class", "display_color": COLOR_MAP["class"]}
        for i in all_items
        if i.get("type") == "class" and i.get("day", "").lower() == today_day.lower()
    ]

    # Today's events (manual + auto-detected bookings)
    todays_events = [
        {**i, "color_category": i.get("category", "personal"),
         "display_color": COLOR_MAP.get(i.get("category", "personal"), COLOR_MAP["other"])}
        for i in all_items
        if i.get("type") == "event" and i.get("date") == today_str
    ]

    # Get tasks due today, overdue, and upcoming (next 3 days)
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    all_tasks = task_resp.get("Items", [])
    due_today = [
        {**t, "color_category": "deadline", "display_color": COLOR_MAP["deadline"]}
        for t in all_tasks
        if t.get("deadline") == today_str and t.get("status") != "done"
    ]
    overdue = [
        {**t, "color_category": "overdue", "display_color": COLOR_MAP["overdue"]}
        for t in all_tasks
        if t.get("deadline") and t.get("deadline") < today_str and t.get("status") != "done"
    ]
    upcoming_3_days = (today + timedelta(days=3)).strftime("%Y-%m-%d")
    upcoming_deadlines = [
        t for t in all_tasks
        if t.get("deadline") and today_str < t.get("deadline") <= upcoming_3_days
        and t.get("status") != "done"
    ]

    # Pending confirmation tasks (from notification extraction)
    pending_confirmations = [
        t for t in all_tasks
        if t.get("status") == "pending_confirmation"
    ]

    # Count unread urgent notifications
    notif_resp = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    cutoff_8h = (datetime.now() - timedelta(hours=8)).isoformat()
    recent_urgent = [
        n for n in notif_resp.get("Items", [])
        if int(n.get("priority", 1)) >= 4
        and n.get("ingested_at", "") >= cutoff_8h
        and not n.get("is_read", False)
    ]

    # Calculate free slots
    all_busy = todays_classes + todays_events
    try:
        free_slots = _calculate_free_slots(all_busy)
    except Exception as e:
        print(f"Error calculating free slots: {e}")
        free_slots = []

    # Build unified timeline (sorted by start_time)
    timeline = sorted(
        todays_classes + todays_events + due_today,
        key=lambda x: x.get("start_time", x.get("deadline", "23:59"))
    )

    return {
        "date": today_str,
        "day": today_day,
        "timeline": timeline,
        "classes": sorted(todays_classes, key=lambda x: x.get("start_time", "")),
        "events": todays_events,
        "due_today": due_today,
        "overdue": overdue,
        "upcoming_deadlines": upcoming_deadlines,
        "pending_confirmations": pending_confirmations,
        "free_slots": free_slots,
        "urgent_unread_count": len(recent_urgent),
        "total_items": len(timeline),
    }


# ── NEW: Free Slot Task Suggester ─────────────────────────────────────────────

@router.post("/free-slot-suggestions")
async def get_free_slot_suggestions(req: FreeSlotSuggestionRequest):
    """
    Sees free gaps in the schedule, checks pending tasks, and suggests what
    the student should work on during each gap.

    Example: "You have a 2-hour free gap on Thursday — You have an assignment
    due Friday, this gap is ideal. Add it?"

    Uses Claude to intelligently match tasks to time slots.
    """
    target_date = req.target_date or date.today().strftime("%Y-%m-%d")
    target_day = datetime.strptime(target_date, "%Y-%m-%d").strftime("%A")

    schedule_table = get_table("schedules")
    task_table = get_table("tasks")

    # Get schedule for the target day
    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_items = sched_resp.get("Items", [])
    day_classes = [
        i for i in all_items
        if i.get("type") == "class" and i.get("day", "").lower() == target_day.lower()
    ]
    day_events = [
        i for i in all_items
        if i.get("type") == "event" and i.get("date") == target_date
    ]
    busy_items = day_classes + day_events

    # Calculate free slots
    free_slots = _calculate_free_slots(busy_items)

    if not free_slots:
        return {
            "suggestions": [],
            "free_slots": [],
            "message": f"No free slots found on {target_day}. Your day is fully booked!",
        }

    # Get pending tasks (not done, sorted by deadline)
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    pending_tasks = [
        t for t in task_resp.get("Items", [])
        if t.get("status") not in ["done", "pending_confirmation"]
    ]
    pending_tasks.sort(key=lambda x: x.get("deadline", "9999"))

    # Claude suggests what to do in each free slot
    suggestions = suggest_free_slot_tasks(
        free_slots=free_slots,
        pending_tasks=pending_tasks[:20],
        schedule_context=busy_items,
    )

    return {
        "date": target_date,
        "day": target_day,
        "free_slots": free_slots,
        "suggestions": suggestions.get("suggestions", []),
        "overall_advice": suggestions.get("overall_advice", ""),
        "pending_tasks_count": len(pending_tasks),
    }


# ── NEW: Detect Bookings & Events from Notifications ─────────────────────────

@router.post("/detect-bookings")
async def detect_bookings_from_notifications(req: DetectBookingsRequest):
    """
    Scans recent notifications for event mentions: train/flight bookings,
    movie tickets, interviews, doctor appointments, etc.

    Detected events are auto-created in the schedule with travel time
    factored in. The student confirms or dismisses each.

    Example: Student mentions a train booking in WhatsApp → app detects it →
    auto-creates a reminder with travel time to the station.
    """
    notif_table = get_table("notifications")
    schedule_table = get_table("schedules")
    now = datetime.now().isoformat()
    cutoff = (datetime.now() - timedelta(hours=req.hours_back)).isoformat()

    # Fetch recent notifications
    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    recent_notifs = [
        n for n in response.get("Items", [])
        if n.get("ingested_at", "") >= cutoff
    ]

    if not recent_notifs:
        return {"events_detected": 0, "events": [], "message": "No recent notifications to scan."}

    # Claude detects bookings/events
    detection_result = detect_booking_events(recent_notifs)
    detected_events = detection_result.get("events", [])

    # Auto-create schedule entries for high-confidence detections
    created_events = []
    for event in detected_events:
        confidence = float(event.get("confidence", 0))
        if confidence < 0.6:
            continue

        event_date = event.get("date")
        event_time = event.get("time")
        if not event_date or not event_time:
            continue

        # Calculate end time (if not provided, default 1 hour)
        end_time = event.get("end_time")
        if not end_time:
            try:
                h, m = event_time.split(":")
                end_h = int(h) + 1
                end_time = f"{end_h:02d}:{m}"
            except (ValueError, IndexError):
                end_time = event_time

        item_id = f"event_{uuid.uuid4().hex[:8]}"
        item = {
            "user_id": req.user_id,
            "item_id": item_id,
            "type": "event",
            "title": event.get("title", "Detected Event"),
            "date": event_date,
            "start_time": event_time,
            "end_time": end_time,
            "category": event.get("event_type", "other"),
            "location": event.get("location"),
            "travel_time_minutes": event.get("travel_time_minutes", 0),
            "reminder_minutes_before": event.get("reminder_minutes_before", 60),
            "booking_reference": event.get("booking_reference"),
            "source": "auto_detected",
            "source_app": event.get("source_app"),
            "confidence": str(confidence),
            "status": "pending_confirmation",
            "created_at": now,
        }
        schedule_table.put_item(Item=item)
        created_events.append(item)

    return {
        "events_detected": len(detected_events),
        "events_created": len(created_events),
        "events": created_events,
        "all_detected": detected_events,
        "notifications_scanned": len(recent_notifs),
    }


@router.post("/confirm-booking/{user_id}/{item_id}")
async def confirm_detected_booking(user_id: str, item_id: str):
    """
    User confirms an auto-detected booking/event.
    Changes status from 'pending_confirmation' to 'confirmed'.
    """
    table = get_table("schedules")
    table.update_item(
        Key={"user_id": user_id, "item_id": item_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "confirmed"},
    )
    return {"confirmed": True, "item_id": item_id}


@router.delete("/dismiss-booking/{user_id}/{item_id}")
async def dismiss_detected_booking(user_id: str, item_id: str):
    """
    User dismisses an auto-detected booking that was wrong.
    Deletes it from the schedule.
    """
    table = get_table("schedules")
    table.delete_item(Key={"user_id": user_id, "item_id": item_id})
    return {"dismissed": True, "item_id": item_id}


# ── NEW: Exam Prep Countdown ─────────────────────────────────────────────────

@router.post("/exam-countdown")
async def get_exam_countdown(req: ExamCountdownRequest):
    """
    Once an exam date is detected (from messages or manual entry):
    1. Shows a countdown (days/hours remaining)
    2. Auto-blocks study slots in the week before the exam
    3. Generates a day-by-day study plan based on available free time

    The generated study slots can be auto-added to the schedule.
    """
    exam_date_obj = datetime.strptime(req.exam_date, "%Y-%m-%d").date()
    days_remaining = (exam_date_obj - date.today()).days

    if days_remaining < 0:
        return {"error": "Exam date is in the past", "days_remaining": days_remaining}

    # Fetch schedule and tasks for context
    schedule_table = get_table("schedules")
    task_table = get_table("tasks")
    notes_table = get_table("notes")

    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    notes_resp = notes_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )

    schedule = sched_resp.get("Items", [])
    pending_tasks = [
        t for t in task_resp.get("Items", [])
        if t.get("status") != "done"
    ]

    # Check if student has notes for this subject
    subject_notes = [
        n for n in notes_resp.get("Items", [])
        if req.exam_subject.lower() in n.get("subject", "").lower()
    ]

    exam_info = {
        "subject": req.exam_subject,
        "date": req.exam_date,
        "time": req.exam_time,
        "days_remaining": days_remaining,
        "has_notes": len(subject_notes) > 0,
        "notes_count": len(subject_notes),
    }

    # Generate AI-powered countdown + study plan
    countdown = generate_exam_countdown(
        exam_info=exam_info,
        schedule=schedule,
        existing_tasks=pending_tasks,
    )

    # Optionally auto-block study slots in the schedule
    study_slots_created = []
    if countdown.get("study_plan"):
        for day_plan in countdown["study_plan"]:
            for slot in day_plan.get("study_slots", []):
                slot_id = f"study_{uuid.uuid4().hex[:8]}"
                item = {
                    "user_id": req.user_id,
                    "item_id": slot_id,
                    "type": "event",
                    "title": f"📚 Study: {req.exam_subject} — {slot.get('focus_topic', 'Review')}",
                    "date": day_plan.get("date"),
                    "start_time": slot.get("start"),
                    "end_time": slot.get("end"),
                    "category": "exam_prep",
                    "notes": slot.get("focus_topic"),
                    "source": "exam_countdown",
                    "exam_subject": req.exam_subject,
                    "exam_date": req.exam_date,
                    "status": "pending_confirmation",
                    "created_at": datetime.now().isoformat(),
                }
                schedule_table.put_item(Item=item)
                study_slots_created.append(item)

    return {
        "countdown": countdown,
        "study_slots_created": len(study_slots_created),
        "study_slots": study_slots_created,
        "notes_available": len(subject_notes),
    }


@router.post("/exam-checklist")
async def get_exam_checklist(req: ExamChecklistRequest):
    """
    Generates AI-powered exam prep checklist based on uploaded notes.
    """
    notes_table = get_table("notes")
    response = notes_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    subject_notes = [
        n for n in response.get("Items", [])
        if req.exam_subject.lower() in n.get("subject", "").lower()
    ]

    exam_date_obj = datetime.strptime(req.exam_date, "%Y-%m-%d").date()
    days_remaining = (exam_date_obj - date.today()).days

    checklist = generate_exam_checklist(
        exam_info={"subject": req.exam_subject, "date": req.exam_date, "days_remaining": days_remaining},
        available_notes=subject_notes,
    )
    return checklist


# ── Helpers ───────────────────────────────────────────────────────────────────

def _calculate_free_slots(busy_items: list) -> list:
    """
    Given a list of schedule items with start/end times, returns free slots
    between 8AM and 10PM.
    """
    def to_minutes(t: str) -> int:
        h, m = t.split(":")
        return int(h) * 60 + int(m)

    def to_time(minutes: int) -> str:
        return f"{minutes // 60:02d}:{minutes % 60:02d}"

    busy = []
    for item in busy_items:
        start = item.get("start_time")
        end = item.get("end_time")
        if start and end:
            busy.append((to_minutes(start), to_minutes(end)))

    busy.sort()
    free = []
    cursor = to_minutes(WORK_START)
    end_of_day = to_minutes(WORK_END)

    for start, end in busy:
        if cursor < start:
            duration = start - cursor
            if duration >= MIN_SLOT_DURATION:
                free.append({
                    "start": to_time(cursor),
                    "end": to_time(start),
                    "duration_minutes": duration,
                })
        cursor = max(cursor, end)

    if cursor < end_of_day and (end_of_day - cursor) >= MIN_SLOT_DURATION:
        free.append({
            "start": to_time(cursor),
            "end": to_time(end_of_day),
            "duration_minutes": end_of_day - cursor,
        })

    return free

