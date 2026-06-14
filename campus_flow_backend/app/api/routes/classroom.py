"""
app/api/routes/classroom.py

Google Classroom integration. This is the closest real analog to the
"Apple Mail -> Calendar" pattern you asked about: Classroom assignments
are ALREADY structured data with real due dates — no extraction guessing
needed, so everything here writes at AUTO_WRITE confidence (1.0).

SETUP REQUIRED (one-time, ~15 min):
  1. Go to https://console.cloud.google.com/
  2. Create a project (or use existing)
  3. Enable "Google Classroom API"
  4. Create OAuth 2.0 Client ID (type: "Web application")
     - Authorized redirect URI: http://YOUR_EC2_IP/api/classroom/oauth/callback
  5. Download client_secret.json, extract client_id + client_secret
  6. Add to .env:
       GOOGLE_CLIENT_ID=...
       GOOGLE_CLIENT_SECRET=...
       GOOGLE_REDIRECT_URI=http://YOUR_EC2_IP/api/classroom/oauth/callback

  pip install google-auth google-auth-oauthlib google-api-python-client
  (add these 3 lines to requirements.txt)

FLOW:
  Flutter opens /api/classroom/oauth/start in a webview
    -> Google login + consent
    -> redirects to /oauth/callback with a code
    -> backend exchanges code for tokens, stores them
    -> Flutter polls /api/classroom/sync periodically (or WorkManager)
    -> sync pulls new coursework, writes directly to schedule + tasks
"""

from fastapi import APIRouter, HTTPException
from fastapi.responses import RedirectResponse, HTMLResponse
from pydantic import BaseModel
from typing import Optional
import uuid
from datetime import datetime, date
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.core.config import settings

router = APIRouter()

# Scopes: read-only access to coursework and announcements
SCOPES = [
    "https://www.googleapis.com/auth/classroom.courses.readonly",
    "https://www.googleapis.com/auth/classroom.coursework.me.readonly",
    "https://www.googleapis.com/auth/classroom.announcements.readonly",
]


# ── Models ────────────────────────────────────────────────────────────────

class ClassroomSyncRequest(BaseModel):
    user_id: str


# ── 1. OAuth flow ────────────────────────────────────────────────────────

@router.get("/oauth/start")
async def classroom_oauth_start(user_id: str):
    """
    Returns the Google consent URL. Flutter opens this in a WebView
    (flutter_inappwebview or url_launcher with external browser).
    """
    if not settings.GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=503, detail="Classroom OAuth not configured")

    from google_auth_oauthlib.flow import Flow

    flow = Flow.from_client_config(
        {
            "web": {
                "client_id": settings.GOOGLE_CLIENT_ID,
                "client_secret": settings.GOOGLE_CLIENT_SECRET,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "redirect_uris": [settings.GOOGLE_REDIRECT_URI],
            }
        },
        scopes=SCOPES,
    )
    flow.redirect_uri = settings.GOOGLE_REDIRECT_URI

    # Pass user_id through `state` so the callback knows who's authenticating
    auth_url, _ = flow.authorization_url(
        access_type="offline",       # gives us a refresh_token
        include_granted_scopes="true",
        prompt="consent",
        state=user_id,
    )
    return {"auth_url": auth_url}


@router.get("/oauth/callback")
async def classroom_oauth_callback(code: str, state: str):
    """
    Google redirects here after consent. `state` carries the user_id.
    Exchanges the code for tokens and stores them in DynamoDB.
    """
    from google_auth_oauthlib.flow import Flow

    user_id = state

    flow = Flow.from_client_config(
        {
            "web": {
                "client_id": settings.GOOGLE_CLIENT_ID,
                "client_secret": settings.GOOGLE_CLIENT_SECRET,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "redirect_uris": [settings.GOOGLE_REDIRECT_URI],
            }
        },
        scopes=SCOPES,
    )
    flow.redirect_uri = settings.GOOGLE_REDIRECT_URI
    flow.fetch_token(code=code)

    creds = flow.credentials
    table = get_table("routine_logs")
    table.put_item(Item={
        "user_id":      user_id,
        "log_id":       "classroom_oauth_token",
        "type":         "classroom_oauth_token",
        "access_token": creds.token,
        "refresh_token": creds.refresh_token,
        "token_uri":    creds.token_uri,
        "client_id":    creds.client_id,
        "client_secret": creds.client_secret,
        "scopes":       ",".join(creds.scopes or []),
        "connected_at": datetime.now().isoformat(),
    })

    # Simple confirmation page — Flutter's WebView detects this and closes itself
    return HTMLResponse("""
        <html><body style="font-family:sans-serif;text-align:center;padding:60px 20px;">
        <h2>✅ Google Classroom connected</h2>
        <p>You can close this window and return to CampusFlow.</p>
        <script>setTimeout(() => window.close(), 1500);</script>
        </body></html>
    """)


@router.get("/status/{user_id}")
async def classroom_connection_status(user_id: str):
    """Whether this user has connected Classroom."""
    table = get_table("routine_logs")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id)
                              & Key("log_id").eq("classroom_oauth_token"),
    )
    connected = len(response.get("Items", [])) > 0
    return {"connected": connected}


@router.delete("/disconnect/{user_id}")
async def classroom_disconnect(user_id: str):
    """Revokes local token storage (does not revoke Google's grant)."""
    table = get_table("routine_logs")
    table.delete_item(Key={"user_id": user_id, "log_id": "classroom_oauth_token"})
    return {"disconnected": True}


# ── 2. Sync — the autonomous pull ──────────────────────────────────────────

@router.post("/sync")
async def sync_classroom(req: ClassroomSyncRequest):
    """
    Pulls all active courses and their coursework. For each assignment
    with a due date, writes DIRECTLY to the task table — confidence is
    1.0 because this is structured API data, not extracted from text.

    This is the autonomous write equivalent of the orchestrator's
    "deadline agent" but for a source that needs no extraction at all.

    Call this:
      - immediately after OAuth connects (first sync)
      - via WorkManager every few hours
    """
    creds = _load_credentials(req.user_id)
    if not creds:
        raise HTTPException(status_code=400, detail="Classroom not connected. Call /oauth/start first.")

    from googleapiclient.discovery import build

    service = build("classroom", "v1", credentials=creds)
    task_table   = get_table("tasks")
    routine_table = get_table("routine_logs")

    # ── Fetch active courses ──────────────────────────────────────────
    courses_resp = service.courses().list(courseStates=["ACTIVE"]).execute()
    courses = courses_resp.get("courses", [])

    tasks_created = []
    tasks_updated = []
    duplicates = 0

    for course in courses:
        course_id = course["id"]
        course_name = course.get("name", "Unknown Course")

        # ── Fetch coursework (assignments) for this course ────────────
        coursework_resp = service.courses().courseWork().list(
            courseId=course_id,
            courseWorkStates=["PUBLISHED"],
        ).execute()
        coursework_items = coursework_resp.get("courseWork", [])

        for item in coursework_items:
            due_date_obj = item.get("dueDate")
            if not due_date_obj:
                continue   # Skip coursework with no deadline — nothing to schedule

            due_date = f"{due_date_obj['year']:04d}-{due_date_obj['month']:02d}-{due_date_obj['day']:02d}"
            due_time_obj = item.get("dueTime", {})
            due_time = f"{due_time_obj.get('hours', 23):02d}:{due_time_obj.get('minutes', 59):02d}" if due_time_obj else "23:59"

            title = item.get("title", "Assignment")
            classroom_id = item.get("id")
            link = item.get("alternateLink")

            # ── Dedupe by Classroom assignment ID (stable, unlike text-extracted dedup) ──
            existing_resp = task_table.query(
                KeyConditionExpression=Key("user_id").eq(req.user_id),
            )
            existing = next((
                t for t in existing_resp.get("Items", [])
                if t.get("classroom_id") == classroom_id
            ), None)

            if existing:
                # Check if due date changed (teacher extended deadline) — update if so
                if existing.get("deadline") != due_date:
                    task_table.update_item(
                        Key={"user_id": req.user_id, "task_id": existing["task_id"]},
                        UpdateExpression="SET deadline = :d, deadline_time = :t, updated_at = :u",
                        ExpressionAttributeValues={
                            ":d": due_date, ":t": due_time, ":u": datetime.now().isoformat(),
                        },
                    )
                    tasks_updated.append({"task_id": existing["task_id"], "title": title, "new_deadline": due_date})
                else:
                    duplicates += 1
                continue

            # ── New assignment — write directly, confidence = 1.0 ──────
            task_id = f"task_{uuid.uuid4().hex[:8]}"
            task_table.put_item(Item={
                "user_id":           req.user_id,
                "task_id":           task_id,
                "title":             title,
                "subject":           course_name,
                "deadline":          due_date,
                "deadline_time":     due_time,
                "status":            "todo",
                "source":            "google_classroom",
                "source_app":        "Google Classroom",
                "source_confidence": "1.00",
                "classroom_id":      classroom_id,
                "classroom_link":    link,
                "auto_added":        True,
                "created_at":        datetime.now().isoformat(),
            })
            tasks_created.append({
                "task_id": task_id, "title": title,
                "subject": course_name, "deadline": due_date,
            })

            # ── Log to activity feed (informational, matches diagram) ──
            routine_table.put_item(Item={
                "user_id":  req.user_id,
                "log_id":   f"activity_{uuid.uuid4().hex[:10]}",
                "type":     "activity_feed",
                "action":   "task_added",
                "title":    title,
                "detail":   f"📚 New assignment from {course_name}: '{title}', due {due_date} {due_time}",
                "ref_id":   task_id,
                "ref_kind": "task",
                "undoable": True,
                "undone":   False,
                "logged_at": datetime.now().isoformat(),
            })

    # ── Update last-sync timestamp ──────────────────────────────────────
    routine_table.update_item(
        Key={"user_id": req.user_id, "log_id": "classroom_oauth_token"},
        UpdateExpression="SET last_synced = :s",
        ExpressionAttributeValues={":s": datetime.now().isoformat()},
    )

    return {
        "courses_checked":  len(courses),
        "tasks_created":    tasks_created,
        "tasks_updated":    tasks_updated,
        "duplicates_skipped": duplicates,
        "synced_at":        datetime.now().isoformat(),
    }


# ── 3. Announcements -> notification-style feed (optional extra) ───────────

@router.post("/sync-announcements")
async def sync_classroom_announcements(req: ClassroomSyncRequest):
    """
    Pulls recent announcements (teacher posts) and feeds them through the
    SAME orchestrator used for WhatsApp/Telegram notifications — so a
    teacher saying "quiz moved to Friday" in an announcement gets the
    same deadline-extraction treatment as a WhatsApp message would.

    This demonstrates the orchestrator being source-agnostic: the event
    shape {"app","title","body"} is the same regardless of where it came
    from.
    """
    creds = _load_credentials(req.user_id)
    if not creds:
        raise HTTPException(status_code=400, detail="Classroom not connected.")

    from googleapiclient.discovery import build
    from app.services.orchestrator import process_event_autonomously

    service = build("classroom", "v1", credentials=creds)
    routine_table = get_table("routine_logs")

    contact_resp = routine_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    contact_subject_map = {
        c.get("contact_name"): c.get("subject")
        for c in contact_resp.get("Items", [])
        if c.get("type") == "contact_subject_link"
    }

    courses_resp = service.courses().list(courseStates=["ACTIVE"]).execute()
    courses = courses_resp.get("courses", [])

    autonomous_results = []

    for course in courses:
        ann_resp = service.courses().announcements().list(
            courseId=course["id"],
            announcementStates=["PUBLISHED"],
            pageSize=10,
        ).execute()

        for ann in ann_resp.get("announcements", []):
            text = ann.get("text", "")
            if not text.strip():
                continue

            raw_event = {
                "app":  "Google Classroom",
                "title": f"{course.get('name','Course')} announcement",
                "body": text,
            }
            result = process_event_autonomously(req.user_id, raw_event, contact_subject_map)
            if result.get("action") not in ["no_action", "discarded"]:
                autonomous_results.append(result)

    return {
        "courses_checked": len(courses),
        "actions_taken":   autonomous_results,
    }


# ── Helpers ──────────────────────────────────────────────────────────────

def _load_credentials(user_id: str):
    """Loads stored OAuth credentials, refreshing the access token if expired."""
    from google.oauth2.credentials import Credentials
    from google.auth.transport.requests import Request as GoogleRequest

    table = get_table("routine_logs")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id)
                              & Key("log_id").eq("classroom_oauth_token"),
    )
    items = response.get("Items", [])
    if not items:
        return None

    token_data = items[0]
    creds = Credentials(
        token=token_data["access_token"],
        refresh_token=token_data["refresh_token"],
        token_uri=token_data["token_uri"],
        client_id=token_data["client_id"],
        client_secret=token_data["client_secret"],
        scopes=token_data["scopes"].split(","),
    )

    if creds.expired and creds.refresh_token:
        creds.refresh(GoogleRequest())
        # Persist the refreshed access token
        table.update_item(
            Key={"user_id": user_id, "log_id": "classroom_oauth_token"},
            UpdateExpression="SET access_token = :t",
            ExpressionAttributeValues={":t": creds.token},
        )

    return creds