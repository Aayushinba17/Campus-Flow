from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime, timedelta

from app.services.claude_service import get_client, get_model

router = APIRouter()


# ─────────────────────────────────────────────
# MODELS
# ─────────────────────────────────────────────

class ScheduleClass(BaseModel):
    time: str          # "09:00"
    subject: str
    room: Optional[str] = ""

class WellnessContext(BaseModel):
    schedule: List[ScheduleClass] = []
    screen_on_minutes_today: int = 0
    last_screen_off_time: Optional[str] = None   # "23:30"
    current_time: str = ""                        # "14:30"
    date_label: str = ""                          # "Monday"
    deadlines_in_48h: int = 0
    unread_urgent_messages: int = 0
    dismissed_reminders: List[str] = []           # ["hydration", "meal_lunch"]
    meal_times: dict = {"breakfast": "08:00", "lunch": "13:00", "dinner": "19:00"}
    # Weekly data (for summary)
    weekly_screen_off_times: List[str] = []       # last 7 days sleep approx
    weekly_busy_days: List[dict] = []             # [{day, classes, deadlines}]


# ─────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────

def parse_time(t: str) -> datetime:
    """Parse HH:MM string into today's datetime."""
    now = datetime.now()
    h, m = map(int, t.split(":"))
    return now.replace(hour=h, minute=m, second=0, microsecond=0)

def is_in_class(schedule: List[ScheduleClass], current_time: str) -> bool:
    """Check if student is currently in a class (assume 1.5hr duration)."""
    try:
        now = parse_time(current_time)
        for cls in schedule:
            start = parse_time(cls.time)
            end = start + timedelta(hours=1, minutes=30)
            if start <= now <= end:
                return True
    except Exception:
        pass
    return False

def get_next_class_time(schedule: List[ScheduleClass], current_time: str) -> Optional[str]:
    """Get time of next upcoming class today."""
    try:
        now = parse_time(current_time)
        upcoming = []
        for cls in schedule:
            cls_time = parse_time(cls.time)
            if cls_time > now:
                upcoming.append(cls.time)
        return min(upcoming) if upcoming else None
    except Exception:
        return None

def minutes_until(target_time: str, current_time: str) -> int:
    """Minutes from current_time to target_time."""
    try:
        t = parse_time(target_time)
        now = parse_time(current_time)
        diff = (t - now).total_seconds() / 60
        return int(diff)
    except Exception:
        return 999


# ─────────────────────────────────────────────
# 1. HYDRATION REMINDERS (context-aware)
# Every 90 min during active hours, pauses during class/sleep
# ─────────────────────────────────────────────

class HydrationRequest(BaseModel):
    context: WellnessContext
    minutes_since_last_reminder: int = 0
    cups_today: int = 0

@router.post("/hydration/check")
async def check_hydration(req: HydrationRequest):
    ctx = req.context
    current = ctx.current_time

    # Don't remind if dismissed recently
    if "hydration" in ctx.dismissed_reminders:
        return {"should_remind": False, "reason": "dismissed"}

    # Don't remind during class
    if is_in_class(ctx.schedule, current):
        return {"should_remind": False, "reason": "in_class"}

    # Don't remind during likely sleep hours (10PM–7AM)
    try:
        hour = int(current.split(":")[0])
        if hour >= 22 or hour < 7:
            return {"should_remind": False, "reason": "sleep_hours"}
    except Exception:
        pass

    # Check 90-minute interval
    if req.minutes_since_last_reminder < 90:
        return {
            "should_remind": False,
            "reason": "too_soon",
            "remind_in_minutes": 90 - req.minutes_since_last_reminder
        }

    # Check if class is starting soon (within 15 min) — delay reminder
    next_class = get_next_class_time(ctx.schedule, current)
    if next_class and minutes_until(next_class, current) < 15:
        return {
            "should_remind": False,
            "reason": "class_starting_soon",
            "remind_after": next_class
        }

    cups_remaining = max(0, 8 - req.cups_today)
    return {
        "should_remind": True,
        "title": "💧 Hydration Check",
        "body": f"Time for water! You've had {req.cups_today}/8 cups today. {cups_remaining} more to go.",
        "cups_today": req.cups_today,
        "cups_remaining": cups_remaining
    }


# ─────────────────────────────────────────────
# 2. SLEEP REMINDER (schedule-aware)
# If 8AM class tomorrow and it's 11:30PM+ with heavy screen activity
# ─────────────────────────────────────────────

class SleepRequest(BaseModel):
    context: WellnessContext
    tomorrow_first_class_time: Optional[str] = None   # "08:00"
    screen_active_last_30min: bool = False

@router.post("/sleep/check")
async def check_sleep(req: SleepRequest):
    ctx = req.context
    current = ctx.current_time

    if "sleep" in ctx.dismissed_reminders:
        return {"should_remind": False, "reason": "dismissed"}

    try:
        hour = int(current.split(":")[0])
        minute = int(current.split(":")[1])
        current_mins = hour * 60 + minute
    except Exception:
        return {"should_remind": False, "reason": "parse_error"}

    # Only active between 10PM and 2AM
    after_10pm = current_mins >= 22 * 60
    if not (after_10pm or hour < 2):
        return {"should_remind": False, "reason": "not_late_yet"}

    # Calculate recommended sleep time
    recommended_sleep_hours = 7.5
    message = "Time to wind down for the night."
    urgency = "normal"

    if req.tomorrow_first_class_time:
        try:
            cls_h, cls_m = map(int, req.tomorrow_first_class_time.split(":"))
            wake_mins = cls_h * 60 + cls_m - 45  # 45 min to get ready
            sleep_mins = wake_mins - int(recommended_sleep_hours * 60)
            sleep_hour = sleep_mins // 60
            sleep_minute = sleep_mins % 60

            now_total = current_mins
            remaining = sleep_mins - now_total
            hours_remaining = abs(remaining) // 60
            mins_remaining = abs(remaining) % 60

            if remaining > 0:
                message = (
                    f"Your first class tomorrow is at {req.tomorrow_first_class_time}. "
                    f"To get {int(recommended_sleep_hours)}h of sleep, you should sleep by "
                    f"{sleep_hour:02d}:{sleep_minute:02d} — that's {hours_remaining}h {mins_remaining}m from now."
                )
            else:
                message = (
                    f"⚠️ You have class at {req.tomorrow_first_class_time} tomorrow. "
                    f"You're already {hours_remaining}h {mins_remaining}m past your ideal sleep time. "
                    f"Wrap up and sleep now to get at least some rest."
                )
                urgency = "urgent"
        except Exception:
            pass

    if not req.screen_active_last_30min:
        return {"should_remind": False, "reason": "screen_not_active"}

    return {
        "should_remind": True,
        "urgency": urgency,
        "title": "🌙 Sleep Reminder",
        "body": message,
        "recommended_bedtime": req.tomorrow_first_class_time
    }


# ─────────────────────────────────────────────
# 3. MEAL TIMING NUDGE
# Reminds at meal hours, skips if in class, avoids nagging if dismissed
# ─────────────────────────────────────────────

class MealRequest(BaseModel):
    context: WellnessContext
    meal_type: str   # "breakfast" | "lunch" | "dinner"

@router.post("/meal/check")
async def check_meal(req: MealRequest):
    ctx = req.context
    meal_type = req.meal_type
    current = ctx.current_time

    dismiss_key = f"meal_{meal_type}"
    if dismiss_key in ctx.dismissed_reminders:
        return {"should_remind": False, "reason": "dismissed"}

    if is_in_class(ctx.schedule, current):
        return {"should_remind": False, "reason": "in_class"}

    meal_time = ctx.meal_times.get(meal_type, "")
    if not meal_time:
        return {"should_remind": False, "reason": "no_meal_time_set"}

    try:
        diff = minutes_until(meal_time, current)
        # Remind within ±20 minutes of meal time
        if abs(diff) > 20:
            return {
                "should_remind": False,
                "reason": "not_meal_time",
                "meal_time": meal_time,
                "minutes_away": diff
            }
    except Exception:
        return {"should_remind": False, "reason": "parse_error"}

    emoji_map = {"breakfast": "🍳", "lunch": "🍱", "dinner": "🍽️"}
    emoji = emoji_map.get(meal_type, "🍴")

    return {
        "should_remind": True,
        "title": f"{emoji} {meal_type.capitalize()} Time",
        "body": f"It's around {meal_time} — time for {meal_type}! Don't skip meals during busy days.",
        "meal_type": meal_type,
        "meal_time": meal_time
    }


# ─────────────────────────────────────────────
# 4. STRESS DENSITY INDICATOR
# Count deadlines + classes + urgent messages in 48h window
# ─────────────────────────────────────────────

class StressRequest(BaseModel):
    context: WellnessContext

@router.post("/stress/calculate")
async def calculate_stress(req: StressRequest):
    ctx = req.context

    # Score: each deadline = 3pts, each class = 1pt, each urgent msg = 2pts
    score = (
        ctx.deadlines_in_48h * 3 +
        len(ctx.schedule) * 1 +
        ctx.unread_urgent_messages * 2
    )

    if score >= 12:
        level = "high"
        card = {
            "show": True,
            "level": "high",
            "title": "🔴 Busy stretch ahead",
            "body": "You have a lot on your plate in the next 48 hours. Take short breaks where you can — even 5 minutes helps.",
            "score": score,
            "breakdown": {
                "deadlines": ctx.deadlines_in_48h,
                "classes": len(ctx.schedule),
                "urgent_messages": ctx.unread_urgent_messages
            }
        }
    elif score >= 6:
        level = "medium"
        card = {
            "show": True,
            "level": "medium",
            "title": "🟡 Moderately busy",
            "body": "Things are picking up. Stay on top of your schedule and don't forget to eat and hydrate.",
            "score": score,
            "breakdown": {
                "deadlines": ctx.deadlines_in_48h,
                "classes": len(ctx.schedule),
                "urgent_messages": ctx.unread_urgent_messages
            }
        }
    else:
        level = "low"
        card = {
            "show": False,
            "level": "low",
            "score": score
        }

    return card


# ─────────────────────────────────────────────
# 5. POMODORO SESSION LOGGING
# ─────────────────────────────────────────────

class PomodoroSession(BaseModel):
    user_id: str
    subject: Optional[str] = None
    duration_minutes: int
    completed: bool
    started_at: str
    ended_at: str

@router.post("/pomodoro")
async def log_pomodoro_session(session: PomodoroSession):
    """Logs a Pomodoro study session for wellness tracking."""
    from app.core.database import get_table
    import uuid
    table = get_table("wellness")
    session_id = f"pomo_{uuid.uuid4().hex[:8]}"
    item = {
        "user_id": session.user_id,
        "date": session.started_at[:10],
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


# ─────────────────────────────────────────────
# 6. WEEKLY WELLNESS SUMMARY
# Every Sunday: infer sleep from screen-off, study vs leisure ratio, busiest day
# ─────────────────────────────────────────────

class WeeklySummaryRequest(BaseModel):
    context: WellnessContext
    study_minutes: int = 0
    leisure_minutes: int = 0
    total_screen_minutes: int = 0

@router.post("/weekly-summary")
async def get_weekly_summary(req: WeeklySummaryRequest):
    ctx = req.context

    # Infer avg sleep from screen-off times
    avg_sleep_hour = None
    if ctx.weekly_screen_off_times:
        total_mins = 0
        for t in ctx.weekly_screen_off_times:
            try:
                h, m = map(int, t.split(":"))
                # Normalize — if hour < 6, treat as next-day (e.g., 1AM = 25:00)
                if h < 6:
                    h += 24
                total_mins += h * 60 + m
            except Exception:
                pass
        avg_mins = total_mins // len(ctx.weekly_screen_off_times)
        avg_sleep_hour = f"{avg_mins // 60 % 24:02d}:{avg_mins % 60:02d}"

    # Busiest day
    busiest_day = None
    if ctx.weekly_busy_days:
        busiest = max(
            ctx.weekly_busy_days,
            key=lambda d: d.get("classes", 0) + d.get("deadlines", 0) * 2
        )
        busiest_day = busiest.get("day", "Unknown")

    # Study vs leisure ratio
    total = req.study_minutes + req.leisure_minutes
    study_pct = int((req.study_minutes / total * 100)) if total > 0 else 0
    leisure_pct = 100 - study_pct

    # Use Claude to generate a human-sounding summary
    prompt = f"""
You are a non-judgmental wellness assistant for a college student.
Generate a brief, warm weekly summary (3-4 sentences max) based on:
- Average screen-off time (proxy for sleep): {avg_sleep_hour or 'unknown'}
- Study vs leisure screen time: {study_pct}% study, {leisure_pct}% leisure  
- Busiest day: {busiest_day or 'unknown'}
- Total screen time: {req.total_screen_minutes} minutes this week

Be supportive, not preachy. Mention one positive observation and one gentle suggestion.
Do not use bullet points. Output plain text only.
"""

    try:
        client = get_client()
        message = client.messages.create(
            model=get_model(),
            max_tokens=200,
            messages=[{"role": "user", "content": prompt}]
        )
        ai_summary = message.content[0].text
    except Exception:
        ai_summary = "Great job getting through another week! Make sure to rest up before the next one."

    return {
        "week_label": ctx.date_label,
        "avg_sleep_time": avg_sleep_hour,
        "busiest_day": busiest_day,
        "study_pct": study_pct,
        "leisure_pct": leisure_pct,
        "ai_summary": ai_summary,
        "stats": {
            "total_screen_minutes": req.total_screen_minutes,
            "study_minutes": req.study_minutes,
            "leisure_minutes": req.leisure_minutes
        }
    }


# ─────────────────────────────────────────────
# 7. SLEEP REMINDER (schedule-aware, GET endpoint)
# ─────────────────────────────────────────────

@router.get("/sleep-reminder/{user_id}")
async def get_sleep_reminder(user_id: str):
    """
    Returns sleep reminder data based on tomorrow's schedule.
    Called by Flutter wellness service.
    """
    from app.core.database import get_table
    from boto3.dynamodb.conditions import Key
    from datetime import date

    schedule_table = get_table("schedules")
    tomorrow_day = (date.today() + timedelta(days=1)).strftime("%A")
    now = datetime.now()
    hour = now.hour

    # Only relevant between 10PM and 1AM
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

    return {
        "should_remind": True,
        "reminder_text": f"You have {first_class.get('subject')} at {first_class_time} tomorrow. Sleep well!",
        "first_class": first_class,
    }