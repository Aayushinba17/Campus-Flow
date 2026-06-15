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
    extract_deadlines_batch,
    generate_missed_call_context,
)
from app.services.orchestrator import process_event_autonomously
import json
from app.services.embedding_service import embed
from app.core.config import settings
 
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
    hours_back: int = settings.DIGEST_HOUR     # Default: last N hours for morning digest

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

    Pipeline per notification:
      1. classify_notifications() — priority scoring for the digest (kept)
      2. process_event_autonomously() — the new orchestrator:
         classify -> extract -> autonomous write (no confirmation tap)

    Max 100 per batch.
    """
    if len(batch.notifications) > settings.MAX_NOTIFICATION_BATCH:
        raise HTTPException(status_code=400, detail=f"Max {settings.MAX_NOTIFICATION_BATCH} notifications per batch")

    notif_table   = get_table("notifications")
    routine_table = get_table("routine_logs")
    now = datetime.now().isoformat()

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

    # ── Step 1: priority classification for digest (unchanged) ─────────
    classified_result = classify_notifications(raw_list)
    classified_map = {c["id"]: c for c in classified_result.get("classified", [])}

    # ── Step 1b: load contact->subject map (for deadline agent context) ─
    contact_resp = routine_table.query(
        KeyConditionExpression=Key("user_id").eq(batch.user_id),
    )
    contact_subject_map = {
        c.get("contact_name"): c.get("subject")
        for c in contact_resp.get("Items", [])
        if c.get("type") == "contact_subject_link"
    }

    saved = []
    autonomous_results = []

    for raw in raw_list:
        cl = classified_map.get(raw["id"], {})
        notif_id = f"notif_{uuid.uuid4().hex[:12]}"

        # Store the raw notification (for digest, search, silence detection)
        item = {
            "user_id":      batch.user_id,
            "notif_id":     notif_id,
            "notification_id": notif_id, # Keep for API backward compatibility
            "app":          raw["app"],
            "app_package":  raw.get("app_package"),
            "title":        raw["title"],
            "body":         raw["body"],
            "timestamp":    raw["timestamp"],
            "contact_name": raw.get("contact_name"),
            "ingested_at":  now,
            "category":     cl.get("category", "unknown"),
            "priority":     cl.get("priority", 1),
            "sender_type":  cl.get("sender_type", "unknown"),
            "summary":      cl.get("summary", raw["title"]),
            "is_read":      False,
        }
        item["embedding"] = json.dumps(embed(f"{item.get('title','')} {item.get('body','')}")) 
        notif_table.put_item(Item=item)
        saved.append(item)

        # ── Step 2: autonomous orchestrator (THE NEW PART) ─────────────
        # Only run the (more expensive) orchestrator on notifications that
        # the cheap priority classifier thinks might be academic/actionable.
        # This keeps cost down — social/promo notifications skip straight
        # through without a second+third Claude call.
        if cl.get("category") in ["academic", "unknown"] or cl.get("priority", 1) >= 3:
            try:
                result = process_event_autonomously(
                    user_id=batch.user_id,  
                    raw_event=raw,
                    contact_subject_map=contact_subject_map,
                )
                result["notification_id"] = notif_id
                result["source_app"] = raw["app"]
                autonomous_results.append(result)
            except Exception as e:
                print(f"Orchestrator error for notif {notif_id}: {e}")

    # ── Build response summary ───────────────────────────────────────
    tasks_created   = [r for r in autonomous_results if r.get("action") == "task_created"]
    events_created  = [r for r in autonomous_results if r.get("action") == "event_created"]
    plans_logged    = [r for r in autonomous_results if r.get("action") == "plan_logged"]
    duplicates      = [r for r in autonomous_results if r.get("action") == "duplicate_skipped"]

    return {
        "saved": len(saved),
        "urgent_count": classified_result.get("urgent_count", 0),
        "autonomous_actions": {
            "tasks_created":   len(tasks_created),
            "events_created":  len(events_created),
            "plans_noted":     len(plans_logged),
            "duplicates_skipped": len(duplicates),
        },
        "tasks":  tasks_created,
        "events": events_created,
        # NOTE: no "new_tasks_pending_confirmation" key anymore —
        # everything above is already written. The activity feed
        # (GET /api/notifications/activity-feed/{user_id}, see below)
        # is where the user reviews-and-undoes if needed.
    }


# ── NEW endpoint: activity feed ─────────────────────────────────────────────

@router.get("/activity-feed/{user_id}")
async def get_activity_feed(user_id: str, limit: int = 20, unread_only: bool = False):
    """
    The passive 'what I did automatically' feed from the architecture
    diagram. Replaces the old 'pending confirmation' list.

    Each entry has undoable=true/false and undone=true/false so the
    Flutter UI can render an Undo button where applicable.
    """
    table = get_table("routine_logs")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    entries = [
        e for e in response.get("Items", [])
        if e.get("type") == "activity_feed"
    ]
    if unread_only:
        entries = [e for e in entries if not e.get("seen", False)]

    entries.sort(key=lambda x: x.get("logged_at", ""), reverse=True)
    return {"activity": entries[:limit], "total": len(entries)}


@router.post("/activity-feed/{user_id}/undo/{log_id}")
async def undo_activity(user_id: str, log_id: str):
    """
    Undoes an autonomous write. Finds the activity entry, then deletes
    the referenced task/event, then marks the activity as undone.
    """
    activity_table = get_table("routine_logs")
    task_table     = get_table("tasks")
    schedule_table = get_table("schedules")

    response = activity_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    entry = next((
        e for e in response.get("Items", [])
        if e.get("log_id") == log_id and e.get("type") == "activity_feed"
    ), None)

    if not entry:
        raise HTTPException(status_code=404, detail="Activity entry not found")
    if not entry.get("undoable"):
        raise HTTPException(status_code=400, detail="This action cannot be undone")
    if entry.get("undone"):
        return {"already_undone": True}

    ref_kind = entry.get("ref_kind")
    ref_id   = entry.get("ref_id")

    if ref_kind == "task" and ref_id:
        task_table.delete_item(Key={"user_id": user_id, "task_id": ref_id})
    elif ref_kind == "event" and ref_id:
        schedule_table.delete_item(Key={"user_id": user_id, "item_id": ref_id})

    activity_table.update_item(
        Key={"user_id": user_id, "log_id": log_id},
        UpdateExpression="SET undone = :u",
        ExpressionAttributeValues={":u": True},
    )

    return {"undone": True, "ref_kind": ref_kind, "ref_id": ref_id}


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
        if (n.get("ingested_at") or "") >= cutoff
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
        if (n.get("ingested_at") or "") >= cutoff
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
        n_id = item.get("notification_id") or item.get("notif_id")
        if n_id in target_ids:
            notif_table.update_item(
                Key={"user_id": req.user_id, "notif_id": item.get("notif_id", n_id)},
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
        and (t.get("deadline") or "9999") >= today
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
        to_scan = [n for n in all_notifs if (n.get("ingested_at") or "") >= cutoff]

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
    today_notifs = [n for n in all_notifs if (n.get("ingested_at") or "") >= today_start]

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
        "total": len(today_notifs),
        "urgent": urgent_unread,
        "urgent_count": urgent_unread,
        "academic": categories.get("academic", 0),
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