from fastapi import APIRouter
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime, timedelta
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import campus_chat, build_student_context, extract_tasks_from_voice

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    user_id: str
    message: str
    session_id: Optional[str] = None   # If continuing a session

class VoiceNoteRequest(BaseModel):
    user_id: str
    transcribed_text: str   # Android SpeechRecognizer output


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/message")
async def send_message(req: ChatMessage):
    """
    Main chat endpoint. Builds full student context and passes to Claude.
    Stores conversation history for context continuity.
    """
    schedule_table = get_table("schedules")
    task_table = get_table("tasks")
    notif_table = get_table("notifications")
    chat_table = get_table("chat_history")

    # Build student context from all data sources
    sched_resp = schedule_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    task_resp = task_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    notif_resp = notif_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )

    cutoff_48h = (datetime.now() - timedelta(hours=48)).isoformat()
    recent_notifs = [
        n for n in notif_resp.get("Items", [])
        if n.get("ingested_at", "") >= cutoff_48h
    ]

    context = build_student_context(
        schedule=sched_resp.get("Items", []),
        tasks=[t for t in task_resp.get("Items", []) if t.get("status") != "done"],
        notifications=recent_notifs,
        profile={"user_id": req.user_id},
    )

    # Fetch last 10 chat messages for this session
    session_id = req.session_id or req.user_id
    history_resp = chat_table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_history = sorted(
        [h for h in history_resp.get("Items", []) if h.get("session_id") == session_id],
        key=lambda x: x.get("created_at", ""),
    )
    # Reconstruct message array for Claude
    chat_history = []
    for h in all_history[-10:]:
        chat_history.append({"role": "user", "content": h.get("user_msg", "")})
        chat_history.append({"role": "assistant", "content": h.get("assistant_msg", "")})

    # Get Claude's response
    response_text = campus_chat(req.message, context, chat_history)

    # Save exchange to history
    msg_id = f"msg_{uuid.uuid4().hex[:12]}"
    chat_table.put_item(Item={
        "user_id": req.user_id,
        "msg_id": msg_id,
        "session_id": session_id,
        "user_msg": req.message,
        "assistant_msg": response_text,
        "created_at": datetime.now().isoformat(),
    })

    return {
        "response": response_text,
        "session_id": session_id,
        "msg_id": msg_id,
    }


@router.post("/voice-to-tasks")
async def process_voice_note(req: VoiceNoteRequest):
    """
    Takes transcribed voice memo text, extracts structured tasks,
    and adds them to the task board.
    """
    extracted = extract_tasks_from_voice(req.transcribed_text)

    task_table = get_table("tasks")
    now = datetime.now().isoformat()
    saved_tasks = []

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
            "status": "todo",
            "source": "voice_note",
            "created_at": now,
        }
        task_table.put_item(Item=item)
        saved_tasks.append(item)

    return {
        "tasks_extracted": len(saved_tasks),
        "tasks": saved_tasks,
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