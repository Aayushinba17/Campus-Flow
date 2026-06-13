from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import (
    classify_notifications,
    generate_morning_digest,
    build_student_context,
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

class NotificationBatch(BaseModel):
    user_id: str
    notifications: List[RawNotification]

class DigestRequest(BaseModel):
    user_id: str
    hours_back: int = 8     # Default: last 8 hours for morning digest

class MarkReadRequest(BaseModel):
    user_id: str
    notification_ids: List[str]


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
            "title": n.title,
            "body": n.body,
            "timestamp": n.timestamp,
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
            "title": raw["title"],
            "body": raw["body"],
            "timestamp": raw["timestamp"],
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
        "generated_at": datetime.now().isoformat(),
    }


@router.get("/recent/{user_id}")
async def get_recent_notifications(user_id: str, hours: int = 24, min_priority: int = 1):
    """
    Returns recent notifications, optionally filtered by minimum priority.
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
    filtered.sort(key=lambda x: int(x.get("priority", 1)), reverse=True)
    return {"notifications": filtered, "total": len(filtered)}


@router.post("/mark-read")
async def mark_notifications_read(req: MarkReadRequest):
    """
    Marks notifications as read after user views digest.
    """
    notif_table = get_table("notifications")
    updated = 0
    for nid in req.notification_ids:
        # DynamoDB update — we need to scan for the item by notification_id
        # In production, consider a GSI on notification_id for efficiency
        response = notif_table.query(
            KeyConditionExpression=Key("user_id").eq(req.user_id),
        )
        for item in response.get("Items", []):
            if item.get("notification_id") == nid:
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
    from datetime import date
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