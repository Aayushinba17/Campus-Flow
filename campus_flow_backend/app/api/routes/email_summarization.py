from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import summarize_email_thread

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class EmailMessage(BaseModel):
    sender: str
    subject: Optional[str] = None
    body: str
    timestamp: Optional[str] = None     # ISO-8601
    is_read: bool = False

class SummarizeThreadRequest(BaseModel):
    """Summarize a batch of email/Slack messages."""
    user_id: str
    messages: List[EmailMessage]
    source_type: str = "email"          # "email"|"slack"|"teams"|"discord"

class SummarizeFromNotificationsRequest(BaseModel):
    """
    Auto-summarize by scanning stored notifications from email/Slack apps.
    No manual message input needed — just pulls from what's already ingested.
    """
    user_id: str
    hours_back: int = 24
    source_apps: Optional[List[str]] = None     # Filter by specific apps


# ── Email / Slack app package mappings ────────────────────────────────────────

EMAIL_SLACK_PACKAGES = {
    # Email apps
    "com.google.android.gm": "Gmail",
    "com.microsoft.office.outlook": "Outlook",
    "com.yahoo.mobile.client.android.mail": "Yahoo Mail",
    "com.samsung.android.email.provider": "Samsung Email",
    # Slack / Teams / Discord
    "com.Slack": "Slack",
    "com.microsoft.teams": "Microsoft Teams",
    "com.discord": "Discord",
    # College-specific
    "com.google.android.apps.classroom": "Google Classroom",
}

EMAIL_SLACK_APPS = set(EMAIL_SLACK_PACKAGES.values())


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/summarize")
async def summarize_messages(req: SummarizeThreadRequest):
    """
    Summarizes a batch of email/Slack messages into 2-line updates.
    Flags action items requiring a reply.

    Use this when the Flutter app has messages to summarize directly
    (e.g. from a Slack integration or email API).
    """
    if not req.messages:
        raise HTTPException(status_code=400, detail="No messages provided")

    messages_dicts = [
        {
            "sender": m.sender,
            "subject": m.subject,
            "body": m.body,
            "timestamp": m.timestamp,
        }
        for m in req.messages
    ]

    result = summarize_email_thread(messages_dicts, source_type=req.source_type)

    return {
        "summaries": result.get("summaries", []),
        "action_items": result.get("action_items", []),
        "total_threads_processed": result.get("total_threads_processed", 0),
        "unread_requiring_action": result.get("unread_requiring_action", 0),
        "source_type": req.source_type,
        "generated_at": datetime.now().isoformat(),
    }


@router.post("/summarize-from-notifications")
async def summarize_from_stored_notifications(req: SummarizeFromNotificationsRequest):
    """
    Auto-summarizes by scanning ALREADY INGESTED notifications from
    email/Slack/Teams apps. No manual input needed.

    This is the magic endpoint — it connects to the notification pipeline:
    1. Student's phone captures Gmail/Slack/Teams notifications
    2. Notifications are ingested via /api/notifications/ingest
    3. This endpoint scans those stored notifications
    4. Claude summarizes threads into 2-line updates
    5. Action items requiring a reply are flagged

    The Flutter app calls this periodically or on-demand.
    """
    notif_table = get_table("notifications")
    cutoff = (datetime.now() - timedelta(hours=req.hours_back)).isoformat()

    # Fetch stored notifications
    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notifs = response.get("Items", [])

    # Filter to email/Slack/Teams apps only
    if req.source_apps:
        # User specified exact app names to filter
        source_set = set(a.lower() for a in req.source_apps)
        email_notifs = [
            n for n in all_notifs
            if (n.get("ingested_at") or "") >= cutoff
            and (
                n.get("app", "").lower() in source_set
                or n.get("app_package", "") in EMAIL_SLACK_PACKAGES
            )
        ]
    else:
        # Auto-detect email/Slack apps from known packages
        email_notifs = [
            n for n in all_notifs
            if (n.get("ingested_at") or "") >= cutoff
            and (
                n.get("app_package", "") in EMAIL_SLACK_PACKAGES
                or n.get("app", "") in EMAIL_SLACK_APPS
            )
        ]

    if not email_notifs:
        return {
            "summaries": [],
            "action_items": [],
            "message": "No email/Slack notifications found in the last "
                       f"{req.hours_back} hours.",
            "scanned_apps": list(EMAIL_SLACK_APPS),
        }

    # Group notifications by app for separate summaries
    by_app = {}
    for n in email_notifs:
        app = n.get("app", EMAIL_SLACK_PACKAGES.get(n.get("app_package", ""), "Unknown"))
        by_app.setdefault(app, []).append(n)

    all_summaries = []
    all_action_items = []

    for app_name, notifs in by_app.items():
        # Determine source type
        source_type = "email"
        if app_name.lower() in ["slack", "microsoft teams", "discord"]:
            source_type = "slack"
        elif app_name.lower() in ["google classroom"]:
            source_type = "academic"

        # Format for Claude
        messages = [
            {
                "sender": n.get("title", n.get("contact_name", "Unknown")),
                "body": n.get("body", ""),
                "content": n.get("body", ""),
                "title": n.get("title", ""),
                "timestamp": n.get("timestamp"),
            }
            for n in notifs
        ]

        result = summarize_email_thread(messages, source_type=source_type)

        # Tag each summary with the source app
        for s in result.get("summaries", []):
            s["source_app"] = app_name
        for a in result.get("action_items", []):
            a["source_app"] = app_name

        all_summaries.extend(result.get("summaries", []))
        all_action_items.extend(result.get("action_items", []))

    # Sort action items by urgency
    urgency_order = {"high": 0, "medium": 1, "low": 2}
    all_action_items.sort(key=lambda x: urgency_order.get(x.get("urgency", "low"), 2))

    return {
        "summaries": all_summaries,
        "action_items": all_action_items,
        "apps_scanned": list(by_app.keys()),
        "notifications_processed": len(email_notifs),
        "unread_requiring_action": sum(
            1 for a in all_action_items if a.get("requires_reply")
        ),
        "generated_at": datetime.now().isoformat(),
    }


@router.get("/action-items/{user_id}")
async def get_pending_action_items(user_id: str):
    """
    Returns all pending action items from email/Slack summaries that
    the student hasn't addressed yet.

    This is a convenience endpoint that re-scans the last 48 hours
    of email/Slack notifications and returns only action items.
    """
    notif_table = get_table("notifications")
    cutoff = (datetime.now() - timedelta(hours=48)).isoformat()

    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    all_notifs = response.get("Items", [])

    # Filter to email/Slack/Teams apps
    email_notifs = [
        n for n in all_notifs
        if (n.get("ingested_at") or "") >= cutoff
        and (
            n.get("app_package", "") in EMAIL_SLACK_PACKAGES
            or n.get("app", "") in EMAIL_SLACK_APPS
        )
    ]

    if not email_notifs:
        return {"action_items": [], "total": 0}

    messages = [
        {
            "sender": n.get("title", "Unknown"),
            "body": n.get("body", ""),
            "content": n.get("body", ""),
            "title": n.get("title", ""),
            "timestamp": n.get("timestamp"),
        }
        for n in email_notifs
    ]

    result = summarize_email_thread(messages, source_type="email")
    action_items = result.get("action_items", [])

    # Only return items requiring reply
    reply_needed = [a for a in action_items if a.get("requires_reply")]

    return {
        "action_items": reply_needed,
        "total": len(reply_needed),
        "all_action_items": action_items,
        "notifications_scanned": len(email_notifs),
    }
