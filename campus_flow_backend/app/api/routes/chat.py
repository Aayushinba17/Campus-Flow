from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, timedelta, date
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import (
    campus_chat,
    build_student_context,
    extract_tasks_from_voice,
    detect_query_intent,
    search_notification_context,
    calculate_study_availability,
)

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    user_id: str
    message: str
    session_id: Optional[str] = None   # If continuing a session

class VoiceNoteRequest(BaseModel):
    user_id: str
    transcribed_text: str   # Android SpeechRecognizer output

class MessageSearchRequest(BaseModel):
    user_id: str
    query: str              # e.g. "Did Prof. Singh send anything about the assignment?"
    hours_back: int = 72    # How far back to search

class StudyTimeRequest(BaseModel):
    user_id: str
    target_date: Optional[str] = None   # YYYY-MM-DD (exam/deadline date)


# ── Routes ────────────────────────────────────────────────────────────────────

# ── ENHANCED: Intelligent Chat with Intent Routing ────────────────────────────

@router.post("/message")
async def send_message(req: ChatMessage):
    """
    ENHANCED main chat endpoint with intelligent intent routing.

    Instead of dumping ALL data into Claude's context (wasteful and slow),
    this endpoint first detects the query intent, then fetches ONLY the
    relevant data. This means:

    - Schedule query → fetches schedule + tasks only
    - Notes query → fetches notes only
    - Message search → fetches notifications only
    - Exam/study query → fetches schedule + tasks for calculation

    This makes responses faster, cheaper, and more accurate because Claude
    isn't distracted by irrelevant data.

    Supports all 4 Instant Q&A types:
    1. Schedule & task queries — "What do I have tomorrow?"
    2. Notes Q&A — "What were the main points from chemistry?"
    3. Message context queries — "Did Prof. Singh send anything?"
    4. Exam & study planner — "How many days until my DSA exam?"
    """
    chat_table = get_table("chat_history")

    # Step 1: Detect intent to know what data to fetch
    intent_result = detect_query_intent(req.message)
    intent = intent_result.get("intent", "general")

    # Step 2: Fetch data based on intent (smart data fetching)
    schedule_data = []
    tasks_data = []
    notifications_data = []
    notes_data = []

    # Always fetch schedule and tasks (lightweight, frequently needed)
    if intent_result.get("needs_schedule", True) or intent in ["schedule", "exam_study", "general"]:
        schedule_table = get_table("schedules")
        sched_resp = schedule_table.query(
            KeyConditionExpression=Key("user_id").eq(req.user_id),
        )
        schedule_data = sched_resp.get("Items", [])

    if intent_result.get("needs_tasks", True) or intent in ["schedule", "exam_study", "general"]:
        task_table = get_table("tasks")
        task_resp = task_table.query(
            KeyConditionExpression=Key("user_id").eq(req.user_id),
        )
        tasks_data = [t for t in task_resp.get("Items", []) if t.get("status") != "done"]

    # Fetch notifications for message context queries
    if intent_result.get("needs_notifications", False) or intent in ["messages", "general"]:
        notif_table = get_table("notifications")
        notif_resp = notif_table.query(
            KeyConditionExpression=Key("user_id").eq(req.user_id),
        )
        cutoff_72h = (datetime.now() - timedelta(hours=72)).isoformat()
        notifications_data = [
            n for n in notif_resp.get("Items", [])
            if (n.get("ingested_at") or "") >= cutoff_72h
        ]
        # Sort by recency for message queries
        notifications_data.sort(key=lambda x: x.get("ingested_at", ""), reverse=True)

    # Fetch notes for notes Q&A
    if intent_result.get("needs_notes", False) or intent == "notes":
        notes_table = get_table("notes")
        notes_resp = notes_table.query(
            KeyConditionExpression=Key("user_id").eq(req.user_id),
        )
        notes_data = notes_resp.get("Items", [])

        # If a subject was extracted from the query, filter notes
        subject_filter = intent_result.get("entities", {}).get("subject")
        if subject_filter:
            filtered = [
                n for n in notes_data
                if subject_filter.lower() in n.get("subject", "").lower()
                or subject_filter.lower() in n.get("title", "").lower()
            ]
            if filtered:
                notes_data = filtered

    # Step 3: Build context with the right data
    # For notes queries, include note summaries and key concepts in context
    notes_context_str = ""
    if notes_data:
        notes_context_str = "\nStudent's uploaded notes:\n" + "\n".join([
            f"- [{n.get('subject', '?')}] {n.get('title', '?')}: {n.get('summary', '')[:200]}"
            f"\n  Key concepts: {', '.join(n.get('key_concepts', [])[:5])}"
            for n in notes_data[:10]
        ])

    context = build_student_context(
        schedule=schedule_data,
        tasks=tasks_data,
        notifications=notifications_data[:50],
        profile={"user_id": req.user_id},
    )

    # Append notes context if relevant
    if notes_context_str:
        context += notes_context_str

    # Step 4: Fetch chat history for continuity
    session_id = req.session_id or req.user_id
    history_resp = chat_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_history = sorted(
        [h for h in history_resp.get("Items", []) if h.get("session_id") == session_id],
        key=lambda x: x.get("created_at", ""),
    )
    chat_history = []
    for h in all_history[-10:]:
        chat_history.append({"role": "user", "content": h.get("user_msg", "")})
        chat_history.append({"role": "assistant", "content": h.get("assistant_msg", "")})

    # Step 5: Get Claude's response
    response_text = campus_chat(req.message, context, chat_history)

    # Step 6: Save exchange to history
    msg_id = f"msg_{uuid.uuid4().hex[:12]}"
    chat_table.put_item(Item={
        "user_id": req.user_id,
        "msg_id": msg_id,
        "session_id": session_id,
        "user_msg": req.message,
        "assistant_msg": response_text,
        "intent": intent,
        "created_at": datetime.now().isoformat(),
    })

    return {
        "response": response_text,
        "session_id": session_id,
        "msg_id": msg_id,
        "intent_detected": intent,
    }


# ── NEW: Message Context Search ──────────────────────────────────────────────

@router.post("/search-messages")
async def search_messages(req: MessageSearchRequest):
    """
    Dedicated message search endpoint for queries like:
    - "Did Prof. Singh send anything about the assignment?"
    - "What did my group chat say about the submission?"
    - "Any messages about the lab report deadline?"

    Claude searches the notification history and returns matching messages
    with relevance scoring and a direct answer.

    This can be called directly OR is used internally by the /message
    endpoint when it detects a message-search intent.
    """
    notif_table = get_table("notifications")
    cutoff = (datetime.now() - timedelta(hours=req.hours_back)).isoformat()

    response = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    notifications = [
        n for n in response.get("Items", [])
        if (n.get("ingested_at") or "") >= cutoff
    ]
    notifications.sort(key=lambda x: x.get("ingested_at", ""), reverse=True)

    if not notifications:
        return {
            "answer": "No notifications found in the last "
                      f"{req.hours_back} hours. Make sure your notification "
                      "listener is active.",
            "matches": [],
            "total_searched": 0,
        }

    # Claude searches the notifications
    search_result = search_notification_context(req.query, notifications[:100])

    # Enrich matches with full notification data
    enriched_matches = []
    for match in search_result.get("matches", []):
        idx = match.get("index", 0) - 1    # Convert 1-indexed to 0-indexed
        if 0 <= idx < len(notifications):
            notif = notifications[idx]
            enriched_matches.append({
                **match,
                "app": notif.get("app"),
                "title": notif.get("title"),
                "body": notif.get("body", "")[:300],
                "timestamp": notif.get("timestamp"),
                "category": notif.get("category"),
            })

    return {
        "answer": search_result.get("answer", ""),
        "matches": enriched_matches,
        "total_searched": len(notifications),
        "found_relevant": search_result.get("found_relevant", 0),
        "query": req.query,
    }


# ── NEW: Study Time Calculator ────────────────────────────────────────────────

@router.post("/study-availability")
async def get_study_availability(req: StudyTimeRequest):
    """
    Calculates exactly how much study time the student has remaining.

    Handles queries like:
    - "How much study time do I have left this week?"
    - "How many free hours before my DSA exam?"
    - "When can I study today?"

    Analyzes the schedule, subtracts class/event time, and returns a
    day-by-day breakdown of available study hours.
    """
    schedule_table = get_table("schedules")
    task_table = get_table("tasks")

    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )

    schedule = sched_resp.get("Items", [])
    tasks = [
        t for t in task_resp.get("Items", [])
        if t.get("status") != "done"
    ]

    result = calculate_study_availability(
        schedule=schedule,
        tasks=tasks,
        target_date=req.target_date,
    )

    return {
        "availability": result,
        "target_date": req.target_date or "next 7 days",
        "calculated_at": datetime.now().isoformat(),
    }


@router.post("/voice-to-tasks")
async def process_voice_note(req: VoiceNoteRequest):
    """
    ENHANCED voice note to task converter.

    Student records a 30-second voice memo — e.g.:
    'remind me to submit the physics assignment by Thursday and ask sir about
    the lab practical.'

    App transcribes it using Android SpeechRecognizer (no API key, device-local),
    passes to Claude, which extracts:
    - 1 task with deadline: "Submit physics assignment" (deadline: Thursday)
    - 1 follow-up item: "Ask sir about the lab practical"

    Both added to DynamoDB task board. Zero typing required.
    """
    extracted = extract_tasks_from_voice(req.transcribed_text)

    task_table = get_table("tasks")
    now = datetime.now().isoformat()
    saved_tasks = []
    saved_follow_ups = []

    # Save main tasks (assignments, reminders, etc.)
    for task in extracted.get("tasks", []):
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        item = {
            "user_id": req.user_id,
            "task_id": task_id,
            "title": task.get("task", ""),
            "deadline": task.get("deadline"),
            "deadline_text": task.get("deadline_text"),
            "type": task.get("type", "other"),
            "priority": task.get("priority", 3),
            "is_follow_up": False,
            "status": "todo",
            "source": "voice_note",
            "created_at": now,
        }
        task_table.put_item(Item=item)
        saved_tasks.append(item)

    # Save follow-up items (ask sir, check with, confirm, etc.)
    for followup in extracted.get("follow_ups", []):
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        item = {
            "user_id": req.user_id,
            "task_id": task_id,
            "title": followup.get("task", ""),
            "type": "follow_up",
            "priority": followup.get("priority", 3),
            "person": followup.get("person"),
            "context": followup.get("context"),
            "is_follow_up": True,
            "status": "todo",
            "source": "voice_note",
            "created_at": now,
        }
        task_table.put_item(Item=item)
        saved_follow_ups.append(item)

    return {
        "tasks_extracted": len(saved_tasks),
        "follow_ups_extracted": len(saved_follow_ups),
        "total_items": len(saved_tasks) + len(saved_follow_ups),
        "tasks": saved_tasks,
        "follow_ups": saved_follow_ups,
        "summary": extracted.get("raw_summary", ""),
        "original_text": req.transcribed_text,
    }


@router.get("/history/{user_id}")
async def get_chat_history(user_id: str, limit: int = 20):
    """
    Returns recent chat history. Used for the conversation log feature.
    """
    table = get_table("chat_history")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    history = sorted(response.get("Items", []), key=lambda x: x.get("created_at", ""), reverse=True)
    return {
        "history": history[:limit],
        "total": len(history),
    }


@router.delete("/history/{user_id}/clear")
async def clear_chat_history(user_id: str):
    """
    Clears all chat history for a user (privacy feature).
    """
    table = get_table("chat_history")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    deleted = 0
    for item in response.get("Items", []):
        table.delete_item(
            Key={"user_id": user_id, "msg_id": item["msg_id"]},
        )
        deleted += 1
    return {"deleted": deleted}