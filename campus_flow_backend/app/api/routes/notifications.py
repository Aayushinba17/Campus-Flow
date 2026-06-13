from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, timedelta, date
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import (
    classify_notifications,
    generate_morning_digest,
    build_student_context,
    generate_missed_call_context,
    extract_deadlines_batch,
)

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class RawNotification(BaseModel):
    app_package: str        # e.g. "com.whatsapp"
    app_name: str           # e.g. "WhatsApp"
    title: str
    body: str
    timestamp: str          # ISO-8601
    notification_id: Optional[str] = None   # Android notification ID
    contact_name: Optional[str] = None      # Sender name (for caller matching)

class NotificationBatch(BaseModel):
    user_id: str
    notifications: List[RawNotification]

class DigestRequest(BaseModel):
    user_id: str
    hours_back: int = 8     # Default: last 8 hours for morning digest

class MarkReadRequest(BaseModel):
    user_id: str
    notification_ids: List[str]

class MissedCallRequest(BaseModel):
    user_id: str
    caller_name: str
    caller_number: Optional[str] = None
    missed_at: str          # ISO-8601 timestamp of the missed call

class DeadlineExtractionRequest(BaseModel):
    user_id: str
    notification_ids: Optional[List[str]] = None  # Specific IDs, or None = scan recent
    hours_back: int = 24    # If no IDs given, scan last N hours


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/ingest")
async def ingest_notifications(batch: NotificationBatch):
    """
    Android app sends batches of notifications here every 30 minutes.
    Claude classifies urgency, extracts deadlines, stores to DynamoDB.
    Max 100 per batch.
    """
    if len(batch.notifications) > 100:
        raise HTTPException(status_code=400, detail="Max 100 notifications per batch")

    notif_table = get_table("notifications")
    task_table = get_table("tasks")
    now = datetime.now().isoformat()

    # Prepare for Claude classification
    raw_list = [
        {
            "id": n.notification_id or uuid.uuid4().hex[:8],
            "app": n.app_name,
            "app_package": n.app_package,
            "title": n.title,
            "body": n.body,
            "timestamp": n.timestamp,
            "contact_name": n.contact_name,
        }
        for n in batch.notifications
    ]

    # Claude classifies the batch
    classified_result = classify_notifications(raw_list)
    classified_map = {
        c["id"]: c for c in classified_result.get("classified", [])
    }

    saved = []
    new_tasks = []

    for raw in raw_list:
        cl = classified_map.get(raw["id"], {})
        notif_id = f"notif_{uuid.uuid4().hex[:12]}"

        item = {
            "user_id": batch.user_id,
            "notification_id": notif_id,
            "app": raw["app"],
            "app_package": raw["app_package"],
            "title": raw["title"],
            "body": raw["body"],
            "timestamp": raw["timestamp"],
            "contact_name": raw.get("contact_name"),
            "ingested_at": now,
            "category": cl.get("category", "unknown"),
            "priority": cl.get("priority", 1),
            "sender_type": cl.get("sender_type", "unknown"),
            "is_deadline": cl.get("is_deadline", False),
            "deadline_task": cl.get("deadline_task"),
            "deadline_date": cl.get("deadline_date"),
            "deadline_confidence": str(cl.get("deadline_confidence", 0)),
            "summary": cl.get("summary", raw["title"]),
            "is_read": False,
        }
        notif_table.put_item(Item=item)
        saved.append(item)

        # Auto-create task if high-confidence deadline found
        if cl.get("is_deadline") and cl.get("deadline_confidence", 0) >= 0.7:
            task_id = f"task_{uuid.uuid4().hex[:8]}"
            task = {
                "user_id": batch.user_id,
                "task_id": task_id,
                "title": cl.get("deadline_task", raw["title"]),
                "deadline": cl.get("deadline_date"),
                "status": "pending_confirmation",   # User must confirm in app
                "source": "notification",
                "source_notification_id": notif_id,
                "source_app": raw["app"],
                "priority": cl.get("priority", 3),
                "created_at": now,
            }
            task_table.put_item(Item=task)
            new_tasks.append(task)

    return {
        "saved": len(saved),
        "deadlines_extracted": len(new_tasks),
        "urgent_count": classified_result.get("urgent_count", 0),
        "new_tasks_pending_confirmation": new_tasks,
    }


@router.post("/digest")
async def get_digest(req: DigestRequest):
    """
    Fetches recent notifications and generates AI morning/evening digest.
    Called by WorkManager on Android at 8 AM daily.
    Returns digest + category split counts for the UI.
    """
    notif_table = get_table("notifications")
    schedule_table = get_table("schedules")
    task_table = get_table("tasks")

    cutoff = (datetime.now() - timedelta(hours=req.hours_back)).isoformat()

    # Fetch recent notifications
    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notifs = response.get("Items", [])
    recent_notifs = [
        n for n in all_notifs
        if n.get("ingested_at", "") >= cutoff
    ]

    # Sort by priority desc
    recent_notifs.sort(key=lambda x: int(x.get("priority", 1)), reverse=True)

    # Count by category for the academic vs social split display
    academic_count = sum(1 for n in recent_notifs if n.get("category") == "academic")
    social_count = sum(1 for n in recent_notifs if n.get("category") == "social")
    promotional_count = sum(1 for n in recent_notifs if n.get("category") == "promotional")
    system_count = sum(1 for n in recent_notifs if n.get("category") == "system")
    unread_count = sum(1 for n in recent_notifs if not n.get("is_read", False))

    # Fetch schedule and tasks for context
    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    schedule = sched_resp.get("Items", [])
    tasks = [t for t in task_resp.get("Items", []) if t.get("status") != "done"]

    context = build_student_context(
        schedule=schedule,
        tasks=tasks,
        notifications=recent_notifs,
        profile={"user_id": req.user_id},
    )

    digest = generate_morning_digest(context, recent_notifs[:30])
    return {
        "digest": digest,
        "notifications_processed": len(recent_notifs),
        "academic_count": academic_count,
        "social_count": social_count,
        "promotional_count": promotional_count,
        "system_count": system_count,
        "unread_count": unread_count,
        "generated_at": datetime.now().isoformat(),
    }


@router.get("/recent/{user_id}")
async def get_recent_notifications(user_id: str, hours: int = 24, min_priority: int = 1, category: Optional[str] = None):
    """
    Returns recent notifications, optionally filtered by minimum priority and category.
    Category filter: academic|social|promotional|system
    """
    notif_table = get_table("notifications")
    cutoff = (datetime.now() - timedelta(hours=hours)).isoformat()

    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    items = response.get("Items", [])
    filtered = [
        n for n in items
        if n.get("ingested_at", "") >= cutoff
        and int(n.get("priority", 1)) >= min_priority
    ]

    # Optional category filter
    if category:
        filtered = [n for n in filtered if n.get("category") == category]

    filtered.sort(key=lambda x: int(x.get("priority", 1)), reverse=True)
    return {"notifications": filtered, "total": len(filtered)}


@router.post("/mark-read")
async def mark_notifications_read(req: MarkReadRequest):
    """
    Marks notifications as read after user views digest.
    """
    notif_table = get_table("notifications")
    updated = 0

    # Fetch all notifications for this user once (avoid re-querying per ID)
    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_items = response.get("Items", [])
    target_ids = set(req.notification_ids)

    for item in all_items:
        if item.get("notification_id") in target_ids:
            notif_table.update_item(
                Key={"user_id": req.user_id, "notification_id": item["notification_id"]},
                UpdateExpression="SET is_read = :r",
                ExpressionAttributeValues={":r": True},
            )
            updated += 1

    return {"marked_read": updated}


@router.get("/deadlines/{user_id}")
async def get_extracted_deadlines(user_id: str, days_ahead: int = 7):
    """
    Returns all tasks extracted from notifications, pending confirmation or confirmed.
    """
    task_table = get_table("tasks")
    response = task_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    today = date.today().isoformat()
    cutoff = (date.today() + timedelta(days=days_ahead)).isoformat()

    tasks = [
        t for t in response.get("Items", [])
        if t.get("source") == "notification"
        and t.get("deadline", "9999") >= today
        and t.get("deadline", "0000") <= cutoff
    ]
    tasks.sort(key=lambda x: x.get("deadline", "9999"))
    return {"deadlines": tasks, "total": len(tasks)}


# ── NEW: Missed Call Context Summary ──────────────────────────────────────────

@router.post("/missed-call-context")
async def get_missed_call_context(req: MissedCallRequest):
    """
    When a PHONE_STATE event triggers a missed call, the Android app calls this
    endpoint. We query the notification buffer for messages from the same contact
    (matched by name) within a ±30-minute window around the missed call timestamp.

    If follow-up messages are found, we combine them with the missed call into a
    single AI-generated context card. This makes the app feel eerily smart —
    it's actually just a time-window join query + Claude summary.

    Example output: "Missed call from Mom — she then texted asking about dinner."
    """
    notif_table = get_table("notifications")
    missed_calls_table = get_table("missed_calls")

    missed_time = datetime.fromisoformat(req.missed_at.replace("Z", "+00:00"))
    window_start = (missed_time - timedelta(minutes=10)).isoformat()
    window_end = (missed_time + timedelta(minutes=30)).isoformat()

    # Query all notifications for this user
    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notifs = response.get("Items", [])

    # Find messages from the same contact within the time window
    # Match by contact_name (case-insensitive) OR by checking if the caller
    # name appears in the notification title/body (WhatsApp/Telegram pattern)
    caller_lower = req.caller_name.lower().strip()

    follow_ups = []
    for n in all_notifs:
        notif_time = n.get("timestamp", "") or n.get("ingested_at", "")
        if not notif_time:
            continue

        # Check if notification falls within the time window
        if notif_time < window_start or notif_time > window_end:
            continue

        # Check if this message is from the same contact
        contact_match = False

        # Match 1: Explicit contact_name field
        if n.get("contact_name") and caller_lower in n["contact_name"].lower():
            contact_match = True

        # Match 2: Caller name appears in notification title (WhatsApp pattern:
        # title is the sender name)
        if not contact_match and caller_lower in n.get("title", "").lower():
            contact_match = True

        # Match 3: Caller name appears in notification body
        if not contact_match and caller_lower in n.get("body", "").lower():
            contact_match = True

        # Exclude the phone app's own missed call notification to avoid circular reference
        phone_packages = {
            "com.android.dialer", "com.google.android.dialer",
            "com.samsung.android.incallui", "com.android.phone",
        }
        if n.get("app_package") in phone_packages:
            continue

        if contact_match:
            follow_ups.append(n)

    # Sort follow-ups by timestamp
    follow_ups.sort(key=lambda x: x.get("timestamp", x.get("ingested_at", "")))

    # Generate AI context summary
    context_result = generate_missed_call_context(
        caller_name=req.caller_name,
        missed_at=req.missed_at,
        follow_up_messages=follow_ups,
    )

    # Store the missed call + context to DynamoDB for history
    call_id = f"call_{uuid.uuid4().hex[:10]}"
    now = datetime.now().isoformat()
    missed_call_item = {
        "user_id": req.user_id,
        "call_id": call_id,
        "caller_name": req.caller_name,
        "caller_number": req.caller_number,
        "missed_at": req.missed_at,
        "follow_up_count": len(follow_ups),
        "has_follow_up": context_result.get("has_follow_up", False),
        "context_summary": context_result.get("context_summary", ""),
        "action_needed": context_result.get("action_needed", False),
        "suggested_action": context_result.get("suggested_action"),
        "urgency": context_result.get("urgency", "low"),
        "created_at": now,
    }
    missed_calls_table.put_item(Item=missed_call_item)

    return {
        "call_id": call_id,
        "missed_call": {
            "caller_name": req.caller_name,
            "caller_number": req.caller_number,
            "missed_at": req.missed_at,
        },
        "follow_up_messages": [
            {
                "app": m.get("app"),
                "title": m.get("title"),
                "body": m.get("body", "")[:200],   # Truncate for response size
                "timestamp": m.get("timestamp"),
                "summary": m.get("summary"),
            }
            for m in follow_ups
        ],
        "context": context_result,
    }


@router.get("/missed-calls/{user_id}")
async def get_missed_call_history(user_id: str, limit: int = 20):
    """
    Returns the history of missed calls with context for display in the app.
    """
    table = get_table("missed_calls")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    calls = sorted(
        response.get("Items", []),
        key=lambda x: x.get("missed_at", ""),
        reverse=True,
    )
    return {"missed_calls": calls[:limit], "total": len(calls)}


# ── NEW: Standalone Deadline Extraction ───────────────────────────────────────

@router.post("/extract-deadlines")
async def extract_deadlines_from_notifications(req: DeadlineExtractionRequest):
    """
    Dedicated deadline extraction endpoint. Can be triggered:
    1. On-demand by the user ("Scan my messages for deadlines")
    2. Periodically as a background job
    3. On specific notification IDs for re-processing

    Separated from /ingest so you can re-scan old notifications without
    re-ingesting them. Uses the dedicated extract_deadlines_batch() Claude
    function with a more thorough deadline-focused prompt.
    """
    notif_table = get_table("notifications")
    task_table = get_table("tasks")
    now = datetime.now().isoformat()

    # Fetch notifications to scan
    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notifs = response.get("Items", [])

    if req.notification_ids:
        # Scan specific notifications by ID
        target_ids = set(req.notification_ids)
        to_scan = [n for n in all_notifs if n.get("notification_id") in target_ids]
    else:
        # Scan recent notifications within the time window
        cutoff = (datetime.now() - timedelta(hours=req.hours_back)).isoformat()
        to_scan = [n for n in all_notifs if n.get("ingested_at", "") >= cutoff]

    if not to_scan:
        return {"deadlines": [], "total_scanned": 0, "new_tasks_created": 0}

    # Run dedicated Claude deadline extraction
    extraction_result = extract_deadlines_batch(to_scan)
    extracted_deadlines = extraction_result.get("deadlines", [])

    # Fetch existing tasks to avoid duplicate deadline creation
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    existing_tasks = task_resp.get("Items", [])
    existing_titles = {t.get("title", "").lower().strip() for t in existing_tasks}
    existing_deadlines = {
        (t.get("title", "").lower().strip(), t.get("deadline", ""))
        for t in existing_tasks
    }

    new_tasks = []
    skipped_duplicates = 0

    for dl in extracted_deadlines:
        # Only create tasks for high-confidence deadlines
        confidence = float(dl.get("confidence", 0))
        if confidence < 0.7:
            continue

        task_title = dl.get("task", "").strip()
        deadline_date = dl.get("deadline_date")

        # Skip if a task with the same title+deadline already exists
        if (task_title.lower(), deadline_date) in existing_deadlines:
            skipped_duplicates += 1
            continue

        # Skip if a task with a very similar title already exists
        if task_title.lower() in existing_titles:
            skipped_duplicates += 1
            continue

        task_id = f"task_{uuid.uuid4().hex[:8]}"
        task = {
            "user_id": req.user_id,
            "task_id": task_id,
            "title": task_title,
            "deadline": deadline_date,
            "deadline_time": dl.get("deadline_time"),
            "status": "pending_confirmation",
            "source": "deadline_extraction",
            "source_app": dl.get("source_app", "unknown"),
            "source_message_preview": dl.get("source_message_preview", ""),
            "priority": 4 if dl.get("urgency") == "high" else 3,
            "confidence": str(confidence),
            "category": dl.get("category", "other"),
            "created_at": now,
        }
        task_table.put_item(Item=task)
        new_tasks.append(task)

        # Track to prevent duplicates within this batch
        existing_titles.add(task_title.lower())
        existing_deadlines.add((task_title.lower(), deadline_date))

    return {
        "deadlines_found": len(extracted_deadlines),
        "new_tasks_created": len(new_tasks),
        "skipped_duplicates": skipped_duplicates,
        "total_scanned": len(to_scan),
        "new_tasks_pending_confirmation": new_tasks,
        "all_extracted": extracted_deadlines,
    }


# ── NEW: Notification Statistics ──────────────────────────────────────────────

@router.get("/stats/{user_id}")
async def get_notification_stats(user_id: str):
    """
    Lightweight endpoint returning notification statistics for the UI:
    - Total notifications today
    - Breakdown by category
    - Unread count (for badges)
    - Top source apps
    - Pending deadline confirmations count

    This avoids the Flutter app having to fetch full notification lists
    just to display badge counts and summary headers.
    """
    notif_table = get_table("notifications")
    task_table = get_table("tasks")

    today_start = datetime.now().replace(hour=0, minute=0, second=0).isoformat()

    # Fetch all notifications
    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    all_notifs = response.get("Items", [])

    # Today's notifications
    today_notifs = [n for n in all_notifs if n.get("ingested_at", "") >= today_start]

    # All unread (not just today)
    all_unread = [n for n in all_notifs if not n.get("is_read", False)]

    # Category breakdown for today
    categories = {}
    for n in today_notifs:
        cat = n.get("category", "unknown")
        categories[cat] = categories.get(cat, 0) + 1

    # Top source apps (today)
    app_counts = {}
    for n in today_notifs:
        app = n.get("app", "Unknown")
        app_counts[app] = app_counts.get(app, 0) + 1
    top_apps = sorted(app_counts.items(), key=lambda x: x[1], reverse=True)[:5]

    # Urgent unread count
    urgent_unread = sum(
        1 for n in all_unread
        if int(n.get("priority", 1)) >= 4
    )

    # Pending deadline confirmations
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    pending_tasks = [
        t for t in task_resp.get("Items", [])
        if t.get("status") == "pending_confirmation"
    ]

    return {
        "total_today": len(today_notifs),
        "unread_total": len(all_unread),
        "urgent_unread": urgent_unread,
        "categories": categories,
        "top_source_apps": [{"app": app, "count": count} for app, count in top_apps],
        "pending_deadline_confirmations": len(pending_tasks),
        "last_notification_at": max(
            (n.get("ingested_at", "") for n in all_notifs), default=None
        ),
    }