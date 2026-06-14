from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, date, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import get_client, get_model

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class DeadlineAlertCheckRequest(BaseModel):
    user_id: str
    hours_ahead: int = 24          # Check deadlines within this window

class SilenceAlertCheckRequest(BaseModel):
    user_id: str
    app_name: str                  # Which group chat to check e.g. "WhatsApp"
    silence_hours: int = 6         # How long of silence to flag

class PreClassNudgeRequest(BaseModel):
    user_id: str
    subject: str
    start_time: str                # HH:MM of the class
    room: Optional[str] = None
    professor: Optional[str] = None

class TravelBufferRequest(BaseModel):
    user_id: str
    event_title: str
    event_time: str                # HH:MM
    is_off_campus: bool = False
    travel_minutes: int = 30       # Default travel buffer

class FocusModeRequest(BaseModel):
    user_id: str
    session_type: str              # "exam" | "study" | "pomodoro"
    duration_minutes: int = 25
    subject: Optional[str] = None

class FocusModeEndRequest(BaseModel):
    user_id: str
    session_id: str

class AlertDismissRequest(BaseModel):
    user_id: str
    alert_id: str
    alert_type: str


# ── 1. Deadline Proximity Alerts ──────────────────────────────────────────────

@router.post("/deadline-check")
async def check_deadline_proximity(req: DeadlineAlertCheckRequest):
    """
    Scans all pending tasks for deadlines within the next N hours.
    Returns rich alert payloads ready to fire as Android notifications.
    Includes: deadline name, source app/message, link to related notes.
    Called by WorkManager every 6 hours.
    """
    task_table  = get_table("tasks")
    notes_table = get_table("notes")

    now       = datetime.now()
    cutoff_dt = now + timedelta(hours=req.hours_ahead)
    today_str = now.strftime("%Y-%m-%d")
    cutoff_str = cutoff_dt.strftime("%Y-%m-%d")

    # Fetch all non-done tasks
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    pending = [
        t for t in task_resp.get("Items", [])
        if t.get("status") not in ["done"]
        and t.get("deadline")
        and today_str <= t["deadline"] <= cutoff_str
    ]

    if not pending:
        return {"alerts": [], "count": 0}

    # For each deadline, check if related notes exist
    notes_resp = notes_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notes = notes_resp.get("Items", [])

    alerts = []
    for task in pending:
        deadline_dt = datetime.strptime(task["deadline"], "%Y-%m-%d")
        hours_remaining = int((deadline_dt - now).total_seconds() / 3600)

        # Find related notes by subject match
        related_note = next((
            n for n in all_notes
            if task.get("title", "").lower() in n.get("title", "").lower()
            or n.get("subject", "").lower() in task.get("title", "").lower()
        ), None)

        # Determine urgency level
        if hours_remaining <= 6:
            urgency = "critical"
        elif hours_remaining <= 12:
            urgency = "high"
        else:
            urgency = "medium"

        alert = {
            "alert_id":        f"deadline_{task.get('task_id', uuid.uuid4().hex[:8])}",
            "type":            "deadline_proximity",
            "urgency":         urgency,
            "title":           f"⏰ Due in {hours_remaining}h: {task.get('title', 'Task')}",
            "body":            _build_deadline_body(task, hours_remaining),
            "task_id":         task.get("task_id"),
            "deadline":        task.get("deadline"),
            "hours_remaining": hours_remaining,
            "source_app":      task.get("source_app", "Unknown"),
            "related_note_id": related_note.get("note_id") if related_note else None,
            "related_note_title": related_note.get("title") if related_note else None,
            "action_deep_link": f"campusflow://task/{task.get('task_id')}",
            "should_fire":     True,
        }
        alerts.append(alert)

    # Sort: critical first
    urgency_order = {"critical": 0, "high": 1, "medium": 2}
    alerts.sort(key=lambda x: urgency_order.get(x["urgency"], 3))

    return {
        "alerts": alerts,
        "count": len(alerts),
        "critical_count": sum(1 for a in alerts if a["urgency"] == "critical"),
    }


def _build_deadline_body(task: dict, hours_remaining: int) -> str:
    source = task.get("source_app", "a message")
    title = task.get("title", "Task")
    if hours_remaining <= 6:
        return f"URGENT: '{title}' is due in {hours_remaining} hours! (Extracted from {source})"
    elif hours_remaining <= 12:
        return f"'{title}' is due today. Found in your {source}."
    else:
        return f"Reminder: '{title}' is due tomorrow. Originally mentioned in {source}."


# ── 2. Unusual Silence Alert ──────────────────────────────────────────────────

@router.post("/silence-check")
async def check_unusual_silence(req: SilenceAlertCheckRequest):
    """
    Detects when a normally active group chat goes silent.
    Cross-references with upcoming deadlines — silence before a deadline
    often means confusion or stress in the group.
    Compares current silence window to historical average for that app.
    """
    notif_table = get_table("notifications")
    task_table  = get_table("tasks")

    now = datetime.now()

    # Fetch all notifications for this app
    notif_resp = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notifs = notif_resp.get("Items", [])
    app_notifs = [
        n for n in all_notifs
        if n.get("app", "").lower() == req.app_name.lower()
    ]

    if len(app_notifs) < 10:
        return {"is_silent": False, "reason": "Not enough history to detect anomaly"}

    # Sort by timestamp
    app_notifs.sort(key=lambda x: x.get("timestamp", "0"))

    # Check current silence: last notification from this app
    latest = app_notifs[-1]
    latest_ts = datetime.fromisoformat(latest.get("ingested_at", now.isoformat()))
    current_silence_hours = (now - latest_ts).total_seconds() / 3600

    if current_silence_hours < req.silence_hours:
        return {
            "is_silent": False,
            "last_message_hours_ago": round(current_silence_hours, 1),
        }

    # Calculate historical average gap between messages (last 14 days)
    cutoff_14d = (now - timedelta(days=14)).isoformat()
    recent_notifs = [n for n in app_notifs if n.get("ingested_at", "") >= cutoff_14d]

    avg_gap_hours = 2.0  # Default assumption
    if len(recent_notifs) >= 2:
        timestamps = [
            datetime.fromisoformat(n.get("ingested_at", now.isoformat()))
            for n in recent_notifs
        ]
        gaps = [(timestamps[i+1] - timestamps[i]).total_seconds() / 3600
                for i in range(len(timestamps)-1)]
        avg_gap_hours = sum(gaps) / len(gaps) if gaps else 2.0

    # Is current silence significantly longer than average?
    is_anomalous = current_silence_hours > (avg_gap_hours * 3)

    if not is_anomalous:
        return {
            "is_silent": False,
            "current_silence_hours": round(current_silence_hours, 1),
            "avg_gap_hours": round(avg_gap_hours, 1),
        }

    # Check if there's an upcoming deadline that makes this more significant
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    upcoming_deadlines = [
        t for t in task_resp.get("Items", [])
        if t.get("deadline", "9999") >= date.today().isoformat()
        and t.get("deadline", "9999") <= (date.today() + timedelta(days=2)).isoformat()
        and t.get("status") not in ["done"]
    ]

    has_upcoming_deadline = len(upcoming_deadlines) > 0
    deadline_context = upcoming_deadlines[0].get("title") if has_upcoming_deadline else None

    # Build alert message
    if has_upcoming_deadline:
        message = (
            f"Your {req.app_name} group has been quiet for "
            f"{int(current_silence_hours)}h — unusual with '{deadline_context}' coming up. "
            f"You might want to check for any updates."
        )
    else:
        message = (
            f"Your {req.app_name} group hasn't had activity in "
            f"{int(current_silence_hours)}h, longer than usual. "
            f"Everything okay?"
        )

    return {
        "is_silent": True,
        "alert_id": f"silence_{uuid.uuid4().hex[:8]}",
        "type": "unusual_silence",
        "app_name": req.app_name,
        "silence_hours": round(current_silence_hours, 1),
        "avg_gap_hours": round(avg_gap_hours, 1),
        "has_upcoming_deadline": has_upcoming_deadline,
        "deadline_context": deadline_context,
        "title": f"🔕 {req.app_name} group unusually quiet",
        "message": message,
        "urgency": "high" if has_upcoming_deadline else "low",
    }


# ── 3. Pre-Class Preparation Nudge ───────────────────────────────────────────

@router.post("/pre-class-nudge")
async def get_pre_class_nudge(req: PreClassNudgeRequest):
    """
    30 minutes before every class:
    - Scans last 2 hours of notifications for messages from that subject's group
    - Uses Claude to generate a contextual 1-line reminder
    - Returns rich notification payload
    Called by Android AlarmManager set at timetable-upload time.
    """
    notif_table = get_table("notifications")

    cutoff = (datetime.now() - timedelta(hours=2)).isoformat()

    notif_resp = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notifs = notif_resp.get("Items", [])

    # Find messages related to this subject (fuzzy match on subject name)
    subject_lower = req.subject.lower()
    relevant = [
        n for n in all_notifs
        if n.get("ingested_at", "") >= cutoff
        and n.get("category") == "academic"
        and (
            subject_lower in n.get("summary", "").lower()
            or subject_lower in n.get("title", "").lower()
            or subject_lower in n.get("body", "").lower()
            or (req.professor and req.professor.lower() in n.get("title", "").lower())
        )
    ]

    # Build reminder with or without context
    if relevant:
        # Use Claude to generate contextual reminder
        context_msgs = "\n".join([
            f"- {n.get('app','?')}: {n.get('summary', n.get('body',''))}"
            for n in relevant[:3]
        ])
        client = get_client()
        response = client.messages.create(
            model=get_model(),
            max_tokens=80,
            system="Write a single helpful class reminder under 20 words. Include the most important context from recent messages. No emoji except at start.",
            messages=[{
                "role": "user",
                "content": (
                    f"Class: {req.subject} in 30 min"
                    f"{f', Room {req.room}' if req.room else ''}"
                    f"{f', Prof {req.professor}' if req.professor else ''}\n"
                    f"Recent messages:\n{context_msgs}\nWrite reminder:"
                )
            }]
        )
        reminder_text = response.content[0].text.strip()
        has_context = True
    else:
        reminder_text = (
            f"{req.subject} in 30 minutes"
            f"{f' — Room {req.room}' if req.room else ''}"
        )
        has_context = False

    return {
        "alert_id":      f"preclass_{uuid.uuid4().hex[:8]}",
        "type":          "pre_class_nudge",
        "subject":       req.subject,
        "start_time":    req.start_time,
        "room":          req.room,
        "professor":     req.professor,
        "title":         f"📚 {req.subject} in 30 min",
        "body":          reminder_text,
        "has_context":   has_context,
        "context_count": len(relevant),
        "relevant_messages": [
            {"app": n.get("app"), "summary": n.get("summary")}
            for n in relevant[:3]
        ],
        "urgency": "medium",
    }


# ── 4. Travel & Commute Buffer Alert ─────────────────────────────────────────

@router.post("/travel-buffer")
async def get_travel_buffer_alert(req: TravelBufferRequest):
    """
    For off-campus events, fires a 'leave now' alert accounting for:
    - Configured travel time
    - Extra buffer (15 min default)
    - Current activity context (already commuting? skip)
    Also checks weather-style flags set by routine context.
    """
    routine_table = get_table("routine_logs")

    # Check current activity context
    ctx_resp = routine_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    contexts = [e for e in ctx_resp.get("Items", []) if e.get("type") == "activity_context"]
    latest_ctx = None
    if contexts:
        latest_ctx = max(contexts, key=lambda x: x.get("timestamp", ""))

    # If already commuting, skip
    if latest_ctx and latest_ctx.get("context") == "commute":
        return {
            "should_alert": False,
            "reason": "Already commuting",
        }

    # Calculate leave time
    event_hour, event_min = map(int, req.event_time.split(":"))
    event_dt = datetime.now().replace(hour=event_hour, minute=event_min, second=0)

    total_buffer_minutes = req.travel_minutes + 15  # 15 min extra buffer
    leave_dt = event_dt - timedelta(minutes=total_buffer_minutes)
    minutes_until_leave = int((leave_dt - datetime.now()).total_seconds() / 60)

    if minutes_until_leave > 15 or minutes_until_leave < -5:
        return {
            "should_alert": False,
            "reason": f"Leave time not imminent ({minutes_until_leave} min away)",
            "leave_at": leave_dt.strftime("%H:%M"),
        }

    location_tag = "off-campus" if req.is_off_campus else "another building"
    urgency = "high" if minutes_until_leave <= 5 else "medium"

    if minutes_until_leave <= 0:
        title = f"🚨 Leave NOW for {req.event_title}"
        body  = f"You should have left {abs(minutes_until_leave)} min ago for your {req.event_time} event!"
    elif minutes_until_leave <= 5:
        title = f"🏃 Time to leave for {req.event_title}"
        body  = f"Leave in {minutes_until_leave} min — it's {location_tag} ({req.travel_minutes} min travel time)."
    else:
        title = f"⏱ Leave in {minutes_until_leave} min for {req.event_title}"
        body  = f"Your {req.event_time} event is {location_tag}. Leave by {leave_dt.strftime('%H:%M')} to arrive on time."

    return {
        "should_alert":         True,
        "alert_id":             f"travel_{uuid.uuid4().hex[:8]}",
        "type":                 "travel_buffer",
        "urgency":              urgency,
        "title":                title,
        "body":                 body,
        "event_title":          req.event_title,
        "event_time":           req.event_time,
        "leave_at":             leave_dt.strftime("%H:%M"),
        "travel_minutes":       req.travel_minutes,
        "minutes_until_leave":  minutes_until_leave,
        "is_off_campus":        req.is_off_campus,
    }


# ── 5. Focus Mode Auto-Trigger ────────────────────────────────────────────────

@router.post("/focus-mode/start")
async def start_focus_mode(req: FocusModeRequest):
    """
    Activates focus mode when student enters exam/study slot.
    - Logs focus session to DB
    - Returns list of apps to block (Flutter triggers DND)
    - Schedules end alert
    - Tracks session for wellness weekly summary
    """
    wellness_table = get_table("wellness")
    routine_table  = get_table("routine_logs")

    session_id = f"focus_{uuid.uuid4().hex[:10]}"
    now = datetime.now()
    end_time = now + timedelta(minutes=req.duration_minutes)

    # Apps to suppress during focus mode
    SOCIAL_PACKAGES = [
        "com.whatsapp",
        "org.telegram.messenger",
        "com.instagram.android",
        "com.snapchat.android",
        "com.twitter.android",
        "com.facebook.katana",
        "com.google.android.youtube",
        "com.zhiliaoapp.musically",   # TikTok
    ]

    # Store focus session
    session_item = {
        "user_id":          req.user_id,
        "date":             now.strftime("%Y-%m-%d"),
        "type":             "focus_session",
        "session_id":       session_id,
        "session_type":     req.session_type,
        "subject":          req.subject or "General",
        "duration_minutes": req.duration_minutes,
        "started_at":       now.isoformat(),
        "scheduled_end":    end_time.isoformat(),
        "status":           "active",
        "ended_at":         None,
    }
    wellness_table.put_item(Item=session_item)

    # Update activity context to "study"
    routine_table.put_item(Item={
        "user_id":  req.user_id,
        "log_id":   f"ctx_{uuid.uuid4().hex[:8]}",
        "type":     "activity_context",
        "context":  "study",
        "headphones_connected": False,
        "screen_on": True,
        "timestamp": now.isoformat(),
        "logged_at": now.isoformat(),
    })

    # Personalized focus message from Claude
    client = get_client()
    response = client.messages.create(
        model=get_model(),
        max_tokens=60,
        system="Write a single motivating focus-mode start message under 15 words. Warm, not pushy.",
        messages=[{
            "role": "user",
            "content": f"Student starting {req.duration_minutes}min {req.session_type} session for {req.subject or 'study'}."
        }]
    )
    focus_message = response.content[0].text.strip()

    return {
        "session_id":          session_id,
        "type":                "focus_mode_start",
        "title":               f"🎯 Focus Mode — {req.subject or req.session_type}",
        "message":             focus_message,
        "duration_minutes":    req.duration_minutes,
        "started_at":          now.isoformat(),
        "ends_at":             end_time.isoformat(),
        "apps_to_block":       SOCIAL_PACKAGES,
        "enable_dnd":          True,
        "allow_calls_from":    [],       # Emergency contacts — configure in onboarding
        "session_type":        req.session_type,
    }


@router.post("/focus-mode/end")
async def end_focus_mode(req: FocusModeEndRequest):
    """
    Ends a focus session. Updates DB, logs actual duration, returns summary.
    """
    wellness_table = get_table("wellness")

    now = datetime.now()

    # Find and update the session
    resp = wellness_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    session = next((
        s for s in resp.get("Items", [])
        if s.get("session_id") == req.session_id and s.get("type") == "focus_session"
    ), None)

    if not session:
        return {"error": "Session not found"}

    started_at = datetime.fromisoformat(session["started_at"])
    actual_minutes = int((now - started_at).total_seconds() / 60)
    scheduled_minutes = int(session.get("duration_minutes", 25))
    completed = actual_minutes >= (scheduled_minutes * 0.8)   # 80% = completed

    wellness_table.update_item(
        Key={"user_id": req.user_id, "date": session["date"]},
        UpdateExpression="SET #st = :s, ended_at = :e, actual_minutes = :a, completed = :c",
        ExpressionAttributeNames={"#st": "status"},
        ExpressionAttributeValues={
            ":s": "completed" if completed else "interrupted",
            ":e": now.isoformat(),
            ":a": actual_minutes,
            ":c": completed,
        },
    )

    # Motivating end message
    client = get_client()
    response = client.messages.create(
        model=get_model(),
        max_tokens=60,
        system="Write a warm 1-sentence focus session end message. Celebrate completion or encourage if cut short. Under 15 words.",
        messages=[{
            "role": "user",
            "content": f"Session: {actual_minutes}min of {scheduled_minutes}min planned. Completed: {completed}. Subject: {session.get('subject','study')}."
        }]
    )
    end_message = response.content[0].text.strip()

    return {
        "session_id":       req.session_id,
        "type":             "focus_mode_end",
        "actual_minutes":   actual_minutes,
        "scheduled_minutes": scheduled_minutes,
        "completed":        completed,
        "message":          end_message,
        "title":            "✅ Focus session complete!" if completed else "Focus session ended",
        "enable_dnd":       False,         # Flutter re-enables notifications
        "apps_to_unblock":  True,
    }


@router.get("/focus-mode/active/{user_id}")
async def get_active_focus_session(user_id: str):
    """
    Returns the current active focus session if any.
    Flutter polls this on app open to restore DND state.
    """
    wellness_table = get_table("wellness")
    resp = wellness_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    active = next((
        s for s in resp.get("Items", [])
        if s.get("type") == "focus_session"
        and s.get("status") == "active"
    ), None)

    if not active:
        return {"has_active_session": False}

    end_time = datetime.fromisoformat(active["scheduled_end"])
    minutes_remaining = max(0, int((end_time - datetime.now()).total_seconds() / 60))

    # Auto-expire sessions that ran over by more than 10 minutes
    if minutes_remaining == 0 and (datetime.now() - end_time).total_seconds() > 600:
        wellness_table.update_item(
            Key={"user_id": user_id, "date": active["date"]},
            UpdateExpression="SET #st = :s",
            ExpressionAttributeNames={"#st": "status"},
            ExpressionAttributeValues={":s": "auto_expired"},
        )
        return {"has_active_session": False}

    return {
        "has_active_session": True,
        "session": active,
        "minutes_remaining": minutes_remaining,
        "ends_at": active["scheduled_end"],
    }


# ── 6. Dismiss / Snooze any alert ────────────────────────────────────────────

@router.post("/dismiss")
async def dismiss_alert(req: AlertDismissRequest):
    """
    Records that an alert was dismissed. Prevents re-firing.
    """
    table = get_table("wellness")
    table.put_item(Item={
        "user_id":     req.user_id,
        "date":        datetime.now().isoformat(),
        "type":        f"dismissed_alert_{req.alert_type}",
        "alert_id":    req.alert_id,
        "dismissed_at": datetime.now().isoformat(),
    })
    return {"dismissed": True}


# ── 7. Get all pending alerts for a user ─────────────────────────────────────

@router.get("/pending/{user_id}")
async def get_pending_alerts(user_id: str):
    """
    Aggregates all alert types and returns everything that should fire right now.
    Flutter calls this on app open and every 15 minutes in background.
    """
    now_str  = datetime.now().strftime("%H:%M")
    today    = date.today().isoformat()

    schedule_table = get_table("schedules")
    task_table     = get_table("tasks")
    notif_table    = get_table("notifications")

    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    task_resp  = task_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )

    today_day = date.today().strftime("%A")
    classes_today = sorted([
        c for c in sched_resp.get("Items", [])
        if c.get("type") == "class" and c.get("day", "") == today_day
    ], key=lambda x: x.get("start_time", ""))

    pending_alerts = []

    # Check each class for 30-min pre-class window
    for cls in classes_today:
        start = cls.get("start_time", "")
        if not start:
            continue
        cls_hour, cls_min = map(int, start.split(":"))
        cls_dt = datetime.now().replace(hour=cls_hour, minute=cls_min, second=0)
        minutes_to_class = int((cls_dt - datetime.now()).total_seconds() / 60)
        if 25 <= minutes_to_class <= 35:       # 30-min window ± 5 min
            pending_alerts.append({
                "alert_type":  "pre_class_nudge",
                "subject":     cls.get("subject"),
                "start_time":  start,
                "room":        cls.get("room"),
                "professor":   cls.get("professor"),
                "priority":    "medium",
            })

    # Check for off-campus events needing travel alerts
    events_today = [
        e for e in sched_resp.get("Items", [])
        if e.get("type") == "event"
        and e.get("date") == today
        and e.get("location", "").lower() in ["off_campus", "off-campus", "external"]
    ]
    for event in events_today:
        pending_alerts.append({
            "alert_type":       "travel_buffer",
            "event_title":      event.get("title"),
            "event_time":       event.get("start_time"),
            "is_off_campus":    True,
            "travel_minutes":   30,
            "priority":         "high",
        })

    # Check critical deadlines (due within 6 hours)
    critical_tasks = [
        t for t in task_resp.get("Items", [])
        if t.get("deadline") == today
        and t.get("status") not in ["done"]
    ]
    for task in critical_tasks:
        pending_alerts.append({
            "alert_type":  "deadline_proximity",
            "task_id":     task.get("task_id"),
            "title":       task.get("title"),
            "deadline":    task.get("deadline"),
            "source_app":  task.get("source_app", "message"),
            "priority":    "critical",
        })

    return {
        "alerts":         pending_alerts,
        "total":          len(pending_alerts),
        "critical_count": sum(1 for a in pending_alerts if a.get("priority") == "critical"),
        "checked_at":     datetime.now().isoformat(),
    }