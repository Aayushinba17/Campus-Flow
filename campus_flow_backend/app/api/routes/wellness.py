from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
import uuid
from datetime import datetime, date, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class PomodoroSession(BaseModel):
    user_id: str
    subject: Optional[str] = None
    duration_minutes: int   # Actual duration (may be less than 25 if interrupted)
    completed: bool         # Did the full session complete?
    started_at: str         # ISO-8601
    ended_at: str


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/pomodoro")
async def log_pomodoro_session(session: PomodoroSession):
    """
    Logs a completed (or interrupted) Pomodoro study session.
    Used for weekly academic pulse and focus analytics.
    """
    table = get_table("wellness")
    session_id = f"pomo_{uuid.uuid4().hex[:8]}"
    item = {
        "user_id": session.user_id,
        "date": session.started_at[:10],    # YYYY-MM-DD as range key
        "type": "pomodoro",
        "session_id": session_id,
        "subject": session.subject or "General",
        "duration_minutes": session.duration_minutes,
        "completed": session.completed,
        "started_at": session.started_at,
        "ended_at": session.ended_at,
    }
    table.put_item(Item=item)
    return {"logged": True, "session_id": session_id}


@router.get("/weekly-summary/{user_id}")
async def get_weekly_summary(user_id: str):
    """
    Sunday summary: study hours, sleep average, task completion rate, stress level.
    Entirely from stored data — no extra AI call needed.
    """
    table = get_table("wellness")
    task_table = get_table("tasks")

    cutoff = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")

    well_resp = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    all_wellness = [w for w in well_resp.get("Items", []) if w.get("date", "") >= cutoff]

    # Study time from Pomodoros
    pomodoros = [w for w in all_wellness if w.get("type") == "pomodoro" and w.get("completed")]
    study_hours = round(sum(p.get("duration_minutes", 0) for p in pomodoros) / 60, 1)

    # Sleep from sleep logs
    sleep_logs = [w for w in all_wellness if w.get("type") == "sleep"]
    avg_sleep = round(
        sum(float(s.get("duration_hours", 0)) for s in sleep_logs) / len(sleep_logs), 1
    ) if sleep_logs else 0.0

    # Task completion
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    all_tasks = [
        t for t in task_resp.get("Items", [])
        if t.get("created_at", "") >= cutoff + "T00:00:00"
    ]
    done_tasks = [t for t in all_tasks if t.get("status") == "done"]
    completion_rate = round(len(done_tasks) / len(all_tasks) * 100) if all_tasks else 0

    # Water reminder compliance
    water_dismissed = len([w for w in all_wellness if w.get("type") == "dismissed_water"])
    # Approximate: 7 days × ~10 reminders/day = 70 expected. Compliance = not dismissed
    water_compliance = max(0, round((1 - water_dismissed / max(70, 1)) * 100))

    # Most studied subject this week
    subject_counts = {}
    for p in pomodoros:
        s = p.get("subject", "General")
        subject_counts[s] = subject_counts.get(s, 0) + p.get("duration_minutes", 0)
    top_subject = max(subject_counts, key=subject_counts.get) if subject_counts else "None"

    return {
        "period": f"{cutoff} to {date.today().isoformat()}",
        "study_hours": study_hours,
        "avg_sleep_hours": avg_sleep,
        "tasks_completed": len(done_tasks),
        "tasks_total": len(all_tasks),
        "completion_rate_percent": completion_rate,
        "water_compliance_percent": water_compliance,
        "top_studied_subject": top_subject,
        "pomodoro_sessions": len(pomodoros),
        "sleep_debt_alert": avg_sleep < 6.5 and len(sleep_logs) >= 3,
        "summary_line": _generate_summary_line(study_hours, avg_sleep, completion_rate),
    }


@router.get("/sleep-reminder/{user_id}")
async def get_sleep_reminder(user_id: str, current_time: str):
    """
    Checks if a sleep reminder should be sent. Returns reminder text if yes.
    Factors in tomorrow's first class from schedule.
    """
    schedule_table = get_table("schedules")
    tomorrow_day = (date.today() + timedelta(days=1)).strftime("%A")
    hour = int(current_time.split(":")[0])

    # Only check between 10PM and 1AM
    if not (22 <= hour <= 23 or 0 <= hour <= 1):
        return {"should_remind": False}

    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    tomorrow_classes = sorted(
        [c for c in sched_resp.get("Items", [])
         if c.get("type") == "class" and c.get("day", "") == tomorrow_day],
        key=lambda x: x.get("start_time", "99:99"),
    )

    if not tomorrow_classes:
        return {"should_remind": False, "reason": "No classes tomorrow"}

    first_class = tomorrow_classes[0]
    first_class_time = first_class.get("start_time", "09:00")
    class_hour = int(first_class_time.split(":")[0])

    # Calculate sleep if sleeping now
    if hour >= 22:
        sleep_start_hour = hour
    else:
        sleep_start_hour = hour + 24

    wake_hour = class_hour - 1     # Wake 1 hour before class
    sleep_hours = wake_hour + (24 - sleep_start_hour) if wake_hour < sleep_start_hour else wake_hour - sleep_start_hour

    if sleep_hours < 7:
        return {
            "should_remind": True,
            "reminder_text": f"You have {first_class.get('subject')} at {first_class_time} tomorrow. Sleeping now gives you only {sleep_hours}h — try to rest soon.",
            "sleep_hours_available": sleep_hours,
            "first_class": first_class,
        }

    return {
        "should_remind": True,
        "reminder_text": f"Winding down? You have {first_class.get('subject')} at {first_class_time} tomorrow. Sleep well!",
        "sleep_hours_available": sleep_hours,
        "first_class": first_class,
    }


# ── Helper ────────────────────────────────────────────────────────────────────

def _generate_summary_line(study_hours: float, avg_sleep: float, completion_rate: int) -> str:
    if study_hours >= 10 and completion_rate >= 80:
        return f"Strong week — {study_hours}h of study and {completion_rate}% tasks done."
    elif avg_sleep < 6:
        return f"Productive but sleep-deprived — aim for more rest next week."
    elif completion_rate < 40:
        return f"Lighter week on tasks — {study_hours}h studied. Next week's a fresh start."
    else:
        return f"{study_hours}h studied, {completion_rate}% tasks done. Steady progress."