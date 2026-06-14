"""
app/services/orchestrator.py

The CampusFlow Brain. Every incoming event — a notification batch, a
Classroom sync, eventually a call transcript — flows through here.

Design principle (the "Apple Mail -> Calendar" pattern):
  High confidence  (>= 0.85)  -> write directly, no user action.
  Medium confidence (0.5-0.85) -> write to an "activity feed" the user
                                   can undo, but does NOT block on it.
  Low confidence   (< 0.5)    -> discard. Better to miss a vague maybe
                                   than to spam the feed with noise.

This file owns:
  - classify_event(): routes a raw event to the right extraction agent
  - extract_deadline() / extract_booking() / extract_plan(): the three
    specialist agents from the architecture diagram
  - resolve_and_write(): the conflict resolver + autonomous DB writes
  - log_activity(): the passive "what I did" feed entry
"""

import json
import uuid
from datetime import datetime, date, timedelta
from typing import Optional

from app.core.database import get_table
from app.services.claude_service import get_client
from app.core.config import settings

# Confidence thresholds — tune these as you collect real demo data
AUTO_WRITE_THRESHOLD   = 0.85   # >= this -> write directly, zero taps
ACTIVITY_FEED_THRESHOLD = 0.50  # >= this -> log to activity feed, still auto-write
                                 # < this  -> discard silently


# ── 1. Event classification (the orchestrator box) ────────────────────────

def classify_event(raw_event: dict) -> dict:
    """
    Given a raw event (notification, Classroom item, etc.), decides which
    specialist agent should handle it. Returns:
      {"agent": "deadline"|"booking"|"plan"|"none", "reasoning": "..."}

    This is a *cheap* triage call — small max_tokens, fast model behavior.
    The specialist agents below do the expensive structured extraction.
    """
    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=120,
        system="""You triage messages for a student assistant. For the given message,
decide which specialist agent (if any) should process it. Return ONLY valid JSON:
{
  "agent": "deadline" | "booking" | "plan" | "none",
  "reasoning": "one short phrase"
}

- "deadline": mentions assignment, exam, submission, due date, project deadline
- "booking": mentions a confirmed reservation — train/flight/movie ticket, interview
  confirmation, appointment confirmation (has a specific date+time already fixed)
- "plan": discusses a *proposed* meetup/study session/event that needs scheduling
  ("let's meet Sunday", "who's free Thursday for the group project")
- "none": promotional, social chit-chat, no actionable scheduling content""",
        messages=[{
            "role": "user",
            "content": f"App: {raw_event.get('app','?')}\nTitle: {raw_event.get('title','')}\nBody: {raw_event.get('body','')}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"agent": "none", "reasoning": "parse_error"}


# ── 2a. Deadline extraction agent ──────────────────────────────────────────

def extract_deadline(raw_event: dict, contact_subject_map: dict) -> Optional[dict]:
    """
    Specialist agent for assignment/exam/deadline extraction.
    contact_subject_map: {"Prof. Sharma": "Physics", ...} from onboarding —
    dramatically improves confidence when the sender is a known professor.
    """
    client = get_client()

    sender_hint = ""
    sender_name = raw_event.get("title", "")
    for contact, subject in contact_subject_map.items():
        if contact.lower() in sender_name.lower():
            sender_hint = f"\nKnown context: this sender is linked to subject '{subject}'."
            break

    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=400,
        system="""Extract a deadline/assignment from this message. Return ONLY valid JSON:
{
  "found": true/false,
  "title": "clear task description",
  "subject": "subject name if identifiable, else null",
  "deadline_date": "YYYY-MM-DD",
  "deadline_time": "HH:MM or null if not specified",
  "confidence": 0.0-1.0
}

Confidence guide:
- 0.9-1.0: explicit date stated ("due March 15", "submit by Friday 11:59pm")
- 0.7-0.85: relative date clearly inferable ("due next Monday", today is known)
- 0.5-0.7: deadline implied but date vague ("submit your assignment soon")
- below 0.5: too ambiguous to act on

Today's date for relative calculations: """ + date.today().isoformat(),
        messages=[{
            "role": "user",
            "content": f"App: {raw_event.get('app','?')}\nFrom: {raw_event.get('title','')}\nMessage: {raw_event.get('body','')}{sender_hint}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    try:
        result = json.loads(raw)
        return result if result.get("found") else None
    except json.JSONDecodeError:
        return None


# ── 2b. Booking extraction agent ───────────────────────────────────────────

def extract_booking(raw_event: dict) -> Optional[dict]:
    """
    Specialist agent for confirmed bookings: trains, flights, movies,
    interviews, appointments. These typically have HIGH confidence because
    confirmation messages are structured by nature.
    """
    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=400,
        system="""Extract a booking/reservation from this confirmation message.
Return ONLY valid JSON:
{
  "found": true/false,
  "title": "e.g. 'Train to Delhi' or 'Interview - TCS'",
  "event_date": "YYYY-MM-DD",
  "event_time": "HH:MM",
  "location": "venue/station/platform if mentioned, else null",
  "category": "travel" | "interview" | "entertainment" | "appointment" | "other",
  "is_off_campus": true/false,
  "confidence": 0.0-1.0
}

Confidence guide:
- 0.9-1.0: this IS a confirmation message with explicit date+time (PNR, ticket, booking ref)
- 0.6-0.85: looks like a confirmation but date/time partially inferred
- below 0.5: not actually a booking confirmation

Today's date: """ + date.today().isoformat(),
        messages=[{
            "role": "user",
            "content": f"App: {raw_event.get('app','?')}\nTitle: {raw_event.get('title','')}\nMessage: {raw_event.get('body','')}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    try:
        result = json.loads(raw)
        return result if result.get("found") else None
    except json.JSONDecodeError:
        return None


# ── 2c. Plan extraction agent (collaborative scheduling seed) ──────────────

def extract_plan(raw_event: dict) -> Optional[dict]:
    """
    Specialist agent for *proposed* plans that aren't confirmed yet.
    These ALWAYS go to the activity feed (never auto-write to schedule)
    because they represent a proposal, not a commitment — but they're the
    seed data for the "collaborative group scheduling" roadmap feature:
    once enough users have the same proposed plan, the app can suggest
    a common free slot.
    """
    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=300,
        system="""Extract a proposed (unconfirmed) plan from this message. Return ONLY valid JSON:
{
  "found": true/false,
  "description": "e.g. 'Group project meetup'",
  "proposed_date": "YYYY-MM-DD or null if vague",
  "proposed_time_window": "e.g. 'afternoon' or 'evening' or null",
  "group_context": "e.g. 'Physics project group' if identifiable",
  "confidence": 0.0-1.0
}

This is for messages like "let's meet Sunday to finish the report" or
"is everyone free Thursday evening?" — proposals, not confirmations.

Today's date: """ + date.today().isoformat(),
        messages=[{
            "role": "user",
            "content": f"App: {raw_event.get('app','?')}\nMessage: {raw_event.get('body','')}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    try:
        result = json.loads(raw)
        return result if result.get("found") else None
    except json.JSONDecodeError:
        return None


# ── 3. Conflict resolver + autonomous writes ───────────────────────────────

def resolve_and_write(user_id: str, agent: str, extracted: dict, source_event: dict) -> dict:
    """
    The "Confidence and conflict resolver" + autonomous write boxes from
    the architecture diagram, combined.

    Returns a dict describing what action was taken — used by the caller
    to build the response summary.
    """
    task_table     = get_table("tasks")
    schedule_table = get_table("schedules")
    activity_table = get_table("routine_logs")   # reused as activity-feed store

    confidence = float(extracted.get("confidence", 0))
    now = datetime.now().isoformat()

    # ── Discard: too low confidence to act on at all ──────────────────
    if confidence < ACTIVITY_FEED_THRESHOLD:
        return {"action": "discarded", "confidence": confidence}

    # ── Decide write status based on confidence tier ──────────────────
    auto_confirmed = confidence >= AUTO_WRITE_THRESHOLD

    if agent == "deadline":
        return _write_deadline(
            user_id, extracted, source_event, auto_confirmed,
            task_table, activity_table,
        )

    elif agent == "booking":
        return _write_booking(
            user_id, extracted, source_event, auto_confirmed,
            schedule_table, activity_table,
        )

    elif agent == "plan":
        # Plans always go to activity feed only — never auto-write to schedule.
        # This is intentional: a *proposal* shouldn't become a calendar
        # commitment without the student (or the group) agreeing.
        return _log_plan_seed(user_id, extracted, source_event, activity_table)

    return {"action": "unhandled_agent", "agent": agent}


def _write_deadline(user_id, extracted, source_event, auto_confirmed, task_table, activity_table) -> dict:
    """
    Checks for duplicate tasks (same title + deadline already exists) before
    writing. This is the 'dedupe' part of the conflict resolver — without it,
    re-reading the same WhatsApp message twice creates two identical tasks.
    """
    deadline_date = extracted.get("deadline_date")
    title         = extracted.get("title", "Untitled task")

    # ── Dedupe check ───────────────────────────────────────────────────
    existing_resp = task_table.query(
        KeyConditionExpression="user_id = :uid",
        ExpressionAttributeValues={":uid": user_id},
    )
    for t in existing_resp.get("Items", []):
        if (t.get("deadline") == deadline_date
                and _titles_similar(t.get("title", ""), title)):
            return {
                "action":  "duplicate_skipped",
                "task_id": t.get("task_id"),
                "title":   title,
            }

    task_id = f"task_{uuid.uuid4().hex[:8]}"
    status  = "todo" if auto_confirmed else "todo"   # both write to todo —
    # the difference is whether it shows in the activity feed (see below)

    task_table.put_item(Item={
        "user_id":           user_id,
        "task_id":           task_id,
        "title":             title,
        "subject":           extracted.get("subject"),
        "deadline":          deadline_date,
        "deadline_time":     extracted.get("deadline_time"),
        "status":            status,
        "source":            "notification",
        "source_app":        source_event.get("app"),
        "source_confidence": confidence_str(extracted),
        "auto_added":        True,
        "created_at":        datetime.now().isoformat(),
    })

    if not auto_confirmed:
        log_activity(activity_table, user_id, {
            "action":  "task_added",
            "title":   title,
            "detail":  f"Added '{title}' (due {deadline_date}) from {source_event.get('app')} — confidence {extracted.get('confidence',0):.2f}",
            "task_id": task_id,
            "undoable": True,
        })

    return {
        "action":     "task_created",
        "task_id":    task_id,
        "title":      title,
        "deadline":   deadline_date,
        "confidence": extracted.get("confidence"),
        "auto_confirmed": auto_confirmed,
    }


def _write_booking(user_id, extracted, source_event, auto_confirmed, schedule_table, activity_table) -> dict:
    """
    Bookings write directly to the schedule table as 'event' type items —
    same table your existing /api/schedule/event endpoint writes to.
    This is the direct Mail -> Calendar equivalent.
    """
    event_date = extracted.get("event_date")
    title      = extracted.get("title", "Booked event")

    # ── Dedupe ─────────────────────────────────────────────────────────
    existing_resp = schedule_table.query(
        KeyConditionExpression="user_id = :uid",
        ExpressionAttributeValues={":uid": user_id},
    )
    for e in existing_resp.get("Items", []):
        if (e.get("type") == "event"
                and e.get("date") == event_date
                and _titles_similar(e.get("title", ""), title)):
            return {"action": "duplicate_skipped", "item_id": e.get("item_id"), "title": title}

    item_id = f"event_{uuid.uuid4().hex[:8]}"
    event_time = extracted.get("event_time", "09:00")

    schedule_table.put_item(Item={
        "user_id":      user_id,
        "item_id":      item_id,
        "type":         "event",
        "title":        title,
        "date":         event_date,
        "start_time":   event_time,
        "end_time":     _add_minutes(event_time, 60),   # default 1hr block
        "category":     extracted.get("category", "other"),
        "location":     "off_campus" if extracted.get("is_off_campus") else extracted.get("location"),
        "notes":        f"Auto-added from {source_event.get('app')}",
        "auto_added":   True,
        "created_at":   datetime.now().isoformat(),
    })

    if not auto_confirmed:
        log_activity(activity_table, user_id, {
            "action":  "event_added",
            "title":   title,
            "detail":  f"Added '{title}' on {event_date} {event_time} from {source_event.get('app')} — confidence {extracted.get('confidence',0):.2f}",
            "item_id": item_id,
            "undoable": True,
        })
    else:
        # Even auto-confirmed bookings get a lightweight feed entry —
        # this is the "Added Physics quiz from group chat" notification
        # from the diagram. It's informational, not a confirmation gate.
        log_activity(activity_table, user_id, {
            "action":  "event_added",
            "title":   title,
            "detail":  f"📅 {title} added to your schedule for {event_date} {event_time}",
            "item_id": item_id,
            "undoable": True,
        })

    return {
        "action":     "event_created",
        "item_id":    item_id,
        "title":      title,
        "date":       event_date,
        "time":       event_time,
        "confidence": extracted.get("confidence"),
        "auto_confirmed": auto_confirmed,
    }


def _log_plan_seed(user_id, extracted, source_event, activity_table) -> dict:
    """
    Stores proposed-plan data for the collaborative scheduling roadmap
    feature. Does NOT write to schedule — proposals aren't commitments.
    """
    plan_id = f"plan_{uuid.uuid4().hex[:8]}"
    activity_table.put_item(Item={
        "user_id":  user_id,
        "log_id":   plan_id,
        "type":     "proposed_plan",
        "description":   extracted.get("description"),
        "proposed_date": extracted.get("proposed_date"),
        "time_window":   extracted.get("proposed_time_window"),
        "group_context": extracted.get("group_context"),
        "confidence":    extracted.get("confidence"),
        "source_app":    source_event.get("app"),
        "logged_at":     datetime.now().isoformat(),
    })
    log_activity(activity_table, user_id, {
        "action": "plan_noted",
        "title":  extracted.get("description", "Proposed plan"),
        "detail": f"Noted a proposed plan from {source_event.get('app')}: \"{extracted.get('description')}\" — nothing scheduled yet.",
        "plan_id": plan_id,
        "undoable": False,
    })
    return {"action": "plan_logged", "plan_id": plan_id}


# ── 4. Activity feed (passive log, not a confirmation queue) ──────────────

def log_activity(activity_table, user_id: str, entry: dict):
    """
    Writes one row to the activity feed. The feed is what the user sees
    on a 'Recent activity' screen — purely informational, with an Undo
    button on undoable entries. It never blocks anything.
    """
    activity_table.put_item(Item={
        "user_id":   user_id,
        "log_id":    f"activity_{uuid.uuid4().hex[:10]}",
        "type":      "activity_feed",
        "action":    entry.get("action"),
        "title":     entry.get("title"),
        "detail":    entry.get("detail"),
        "ref_id":    entry.get("task_id") or entry.get("item_id") or entry.get("plan_id"),
        "ref_kind":  "task" if entry.get("task_id") else "event" if entry.get("item_id") else "plan",
        "undoable":  entry.get("undoable", False),
        "undone":    False,
        "logged_at": datetime.now().isoformat(),
    })


# ── Helpers ──────────────────────────────────────────────────────────────

def _titles_similar(a: str, b: str) -> bool:
    """Cheap similarity check for dedup — normalize and compare word overlap."""
    wa = set(a.lower().split())
    wb = set(b.lower().split())
    if not wa or not wb:
        return False
    overlap = len(wa & wb) / max(len(wa), len(wb))
    return overlap >= 0.6


def _add_minutes(time_str: str, minutes: int) -> str:
    h, m = map(int, time_str.split(":"))
    total = h * 60 + m + minutes
    return f"{(total // 60) % 24:02d}:{total % 60:02d}"


def confidence_str(extracted: dict) -> str:
    return f"{float(extracted.get('confidence', 0)):.2f}"


# ── 5. Top-level entry point ───────────────────────────────────────────────

def process_event_autonomously(user_id: str, raw_event: dict, contact_subject_map: dict) -> dict:
    """
    Full pipeline for ONE event, end to end:
      classify -> extract (specialist agent) -> resolve_and_write

    Called once per notification in notifications.py's /ingest endpoint
    (replacing the old single classify_notifications call for the
    deadline-extraction portion — priority scoring stays as-is).
    """
    classification = classify_event(raw_event)
    agent = classification.get("agent", "none")

    if agent == "none":
        return {"action": "no_action", "reasoning": classification.get("reasoning")}

    extracted = None
    if agent == "deadline":
        extracted = extract_deadline(raw_event, contact_subject_map)
    elif agent == "booking":
        extracted = extract_booking(raw_event)
    elif agent == "plan":
        extracted = extract_plan(raw_event)

    if not extracted:
        return {"action": "extraction_failed", "agent": agent}

    result = resolve_and_write(user_id, agent, extracted, raw_event)
    result["agent"] = agent
    return result