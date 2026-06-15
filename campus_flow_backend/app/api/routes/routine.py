from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional, Dict
import uuid
from datetime import datetime, timedelta
from boto3.dynamodb.conditions import Key, Attr

from app.core.database import get_table
from app.services.claude_service import generate_routine_insights

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class AppUsageEntry(BaseModel):
    app_package: str
    app_name: str
    usage_minutes: int
    hour_of_day: int        # 0-23
    day_of_week: str        # "Monday" etc.
    date: str               # YYYY-MM-DD

class UsageLogBatch(BaseModel):
    user_id: str
    entries: List[AppUsageEntry]

class ActivityContextUpdate(BaseModel):
    user_id: str
    context: str            # "study"|"workout"|"commute"|"idle"|"class"
    headphones_connected: bool = False
    screen_on: bool = True
    timestamp: str

class SleepLogEntry(BaseModel):
    user_id: str
    screen_off_time: str    # ISO-8601 — when screen went off
    screen_on_time: str     # ISO-8601 — when screen came back on
    date: str               # YYYY-MM-DD

class BatteryLogEntry(BaseModel):
    user_id: str
    battery_percent: int
    timestamp: str
    hour_of_day: int


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/usage-log")
async def log_app_usage(batch: UsageLogBatch):
    """
    Android sends hourly UsageStatsManager data.
    Stores to DynamoDB for heatmap and routine analysis.
    """
    table = get_table("routine_logs")
    saved = 0
    for entry in batch.entries:
        log_id = f"usage_{uuid.uuid4().hex[:8]}"
        item = {
            "user_id": batch.user_id,
            "log_id": log_id,
            "type": "app_usage",
            "app_package": entry.app_package,
            "app_name": entry.app_name,
            "usage_minutes": entry.usage_minutes,
            "hour_of_day": entry.hour_of_day,
            "day_of_week": entry.day_of_week,
            "date": entry.date,
            "logged_at": datetime.now().isoformat(),
        }
        table.put_item(Item=item)
        saved += 1
    return {"saved": saved}


@router.get("/heatmap/{user_id}")
async def get_usage_heatmap(user_id: str, days: int = 7):
    """
    Returns 7×24 grid of usage data for the heatmap widget.
    Each cell = total minutes across all apps for that [day, hour].
    """
    table = get_table("routine_logs")
    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    entries = [
        e for e in response.get("Items", [])
        if e.get("type") == "app_usage" and e.get("date", "") >= cutoff
    ]

    # Build 7×24 grid: {day_of_week: {hour: total_minutes}}
    DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    grid: Dict[str, Dict[int, int]] = {day: {h: 0 for h in range(24)} for day in DAYS}

    for e in entries:
        day = e.get("day_of_week")
        hour = int(e.get("hour_of_day", 0))
        mins = int(e.get("usage_minutes", 0))
        if day in grid:
            grid[day][hour] += mins

    # Flatten for easy Flutter rendering
    cells = []
    day_totals = {day: 0 for day in DAYS}
    for day in DAYS:
        for hour in range(24):
            mins = grid[day][hour]
            cells.append({
                "day": day,
                "hour": hour,
                "minutes": mins,
            })
            day_totals[day] += mins

    total_minutes = sum(day_totals.values())
    avg_daily_minutes = int(total_minutes / len(DAYS)) if DAYS else 0

    max_minutes = max(c["minutes"] for c in cells) if cells else 1
    # Add normalized 0-1 intensity for color rendering
    for c in cells:
        c["intensity"] = round(c["minutes"] / max_minutes, 2) if max_minutes > 0 else 0

    return {
        "grid": cells,
        "days": days,
        "max_minutes": max_minutes,
        "heatmap": day_totals,
        "total_minutes": total_minutes,
        "avg_daily_minutes": avg_daily_minutes,
    }


@router.post("/activity-context")
async def update_activity_context(req: ActivityContextUpdate):
    """
    Android sends activity context updates every 15 minutes.
    Used to suppress irrelevant reminders (e.g. during workout).
    """
    table = get_table("routine_logs")
    log_id = f"ctx_{uuid.uuid4().hex[:8]}"
    item = {
        "user_id": req.user_id,
        "log_id": log_id,
        "type": "activity_context",
        "context": req.context,
        "headphones_connected": req.headphones_connected,
        "screen_on": req.screen_on,
        "timestamp": req.timestamp,
        "logged_at": datetime.now().isoformat(),
    }
    table.put_item(Item=item)
    return {"saved": True, "context": req.context}


@router.get("/current-context/{user_id}")
async def get_current_context(user_id: str):
    """
    Returns the most recent activity context for reminder suppression decisions.
    """
    table = get_table("routine_logs")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    contexts = [
        e for e in response.get("Items", [])
        if e.get("type") == "activity_context"
    ]
    if not contexts:
        return {"context": "unknown", "headphones": False}

    latest = max(contexts, key=lambda x: x.get("timestamp", ""))
    return {
        "context": latest.get("context", "unknown"),
        "headphones_connected": latest.get("headphones_connected", False),
        "screen_on": latest.get("screen_on", True),
        "last_updated": latest.get("timestamp"),
    }


@router.post("/sleep-log")
async def log_sleep(entry: SleepLogEntry):
    """
    Android logs screen on/off events. Backend infers sleep duration.
    Sleep = longest screen-off window between 10PM and 8AM.
    """
    table = get_table("wellness")
    off_time = datetime.fromisoformat(entry.screen_off_time)
    on_time = datetime.fromisoformat(entry.screen_on_time)
    duration_minutes = int((on_time - off_time).total_seconds() / 60)

    # Only log if it looks like a sleep window (>3 hours, between 9PM-9AM)
    if duration_minutes < 180:
        return {"logged": False, "reason": "Duration too short to be sleep"}

    off_hour = off_time.hour
    if not (21 <= off_hour <= 23 or 0 <= off_hour <= 2):
        return {"logged": False, "reason": "Not in sleep window hours"}

    item = {
        "user_id": entry.user_id,
        "date": entry.date,
        "type": "sleep",
        "screen_off_time": entry.screen_off_time,
        "screen_on_time": entry.screen_on_time,
        "duration_minutes": duration_minutes,
        "duration_hours": round(duration_minutes / 60, 1),
        "logged_at": datetime.now().isoformat(),
    }
    table.put_item(Item=item)
    return {"logged": True, "duration_hours": round(duration_minutes / 60, 1)}


@router.get("/sleep-summary/{user_id}")
async def get_sleep_summary(user_id: str, days: int = 7):
    """
    Returns sleep duration per night for the last N days.
    """
    table = get_table("wellness")
    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")

    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
        FilterExpression=Attr("date").gte(cutoff),
    )
    sleep_logs = [
        e for e in response.get("Items", [])
        if e.get("type") == "sleep" and e.get("date", "") >= cutoff
    ]
    sleep_logs.sort(key=lambda x: x.get("date", ""))

    avg_hours = 0.0
    if sleep_logs:
        avg_hours = round(sum(float(s.get("duration_hours", 0)) for s in sleep_logs) / len(sleep_logs), 1)

    return {
        "sleep_logs": sleep_logs,
        "average_hours": avg_hours,
        "days_tracked": len(sleep_logs),
        "sleep_debt_alert": avg_hours < 6.5 and len(sleep_logs) >= 3,
    }


@router.post("/generate-insights/{user_id}")
async def generate_insights(user_id: str):
    """
    Triggered after 7 days of data. Claude analyzes logs and returns insights.
    Called by Android WorkManager after initial observation period.
    """
    table = get_table("routine_logs")
    schedule_table = get_table("schedules")

    # Fetch last 7 days of usage logs
    cutoff = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    usage_logs = [
        e for e in response.get("Items", [])
        if e.get("type") == "app_usage" and e.get("date", "") >= cutoff
    ]

    # Fetch schedule for context
    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    schedule = sched_resp.get("Items", [])

    if len(usage_logs) < 10:
        return {"error": "Not enough data yet. Keep using the app for a few more days."}

    insights = generate_routine_insights(usage_logs, schedule)
    return insights


@router.post("/battery-log")
async def log_battery(entry: BatteryLogEntry):
    """
    Logs hourly battery drain for focus/distraction correlation.
    """
    table = get_table("routine_logs")
    log_id = f"bat_{uuid.uuid4().hex[:8]}"
    item = {
        "user_id": entry.user_id,
        "log_id": log_id,
        "type": "battery",
        "battery_percent": entry.battery_percent,
        "timestamp": entry.timestamp,
        "hour_of_day": entry.hour_of_day,
        "logged_at": datetime.now().isoformat(),
    }
    table.put_item(Item=item)
    return {"saved": True}