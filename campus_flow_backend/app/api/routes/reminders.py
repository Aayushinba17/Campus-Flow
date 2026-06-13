from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, date, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import enhance_reminder, analyze_stress_density

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class PreClassReminderRequest(BaseModel):
    user_id: str
    class_info: dict        # {subject, start_time, end_time, room, professor}
    minutes_before: int = 30

class WellnessReminderCheckRequest(BaseModel):
    user_id: str
    reminder_type: str      # "water"|"meal"|"sleep"|"break"
    current_time: str       # HH:MM

class StressDensityRequest(BaseModel):
    user_id: str


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/pre-class")
async def get_pre_class_reminder(req: PreClassReminderRequest):
    """
    30 minutes before a class, fetch recent relevant messages and
    enhance the reminder with context.
    """
    notif_table = get_table("notifications")
    cutoff = (datetime.now() - timedelta(hours=2)).isoformat()

    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    recent = [
        n for n in response.get("Items", [])
        if n.get("ingested_at", "") >= cutoff
        and n.get("category") == "academic"
    ]

    enhanced_text = enhance_reminder(req.class_info, recent)
    return {
        "reminder_text": enhanced_text,
        "class": req.class_info,
        "fire_at_minutes_before": req.minutes_before,
        "context_messages_found": len(recent),
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
    current_time = req.current_time   # HH:MM

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

    # Check if reminder was recently dismissed (within 3 hours for meals, 90 min for water)
    cool_down_minutes = {"water": 90, "meal": 180, "sleep": 240, "break": 120}
    cool_down = cool_down_minutes.get(req.reminder_type, 90)
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
async def dismiss_wellness_reminder(user_id: str, reminder_type: str):
    """
    Records that a wellness reminder was dismissed. Prevents re-firing within cool-down.
    """
    table = get_table("wellness")
    item = {
        "user_id": user_id,
        "date": datetime.now().isoformat(),
        "type": f"dismissed_{reminder_type}",
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
    User confirms a deadline that was auto-extracted from a notification.
    Moves it from 'pending_confirmation' to 'todo'.
    """
    table = get_table("tasks")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    task = next((t for t in response.get("Items", []) if t.get("task_id") == task_id), None)
    if not task:
        from fastapi import HTTPException
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
        from fastapi import HTTPException
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


from typing import Optional