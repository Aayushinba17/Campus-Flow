from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import process_notes, ask_notes
from app.services.aws_service import upload_to_s3

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class NoteTextRequest(BaseModel):
    user_id: str
    text: str
    subject: Optional[str] = None
    title: Optional[str] = None

class NotesQARequest(BaseModel):
    user_id: str
    question: str
    subject_filter: Optional[str] = None   # Optional: limit to a specific subject


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/process-text")
async def process_note_text(req: NoteTextRequest):
    """
    Student pastes lecture notes as text.
    Claude extracts: mindmap, key concepts, tasks, summary.
    This is the bridge to your existing notes project.
    """
    if len(req.text.strip()) < 50:
        raise HTTPException(status_code=400, detail="Notes too short — minimum 50 characters")

    processed = process_notes(req.text, subject=req.subject)

    notes_table = get_table("notes")
    task_table = get_table("tasks")
    now = datetime.now().isoformat()

    note_id = f"note_{uuid.uuid4().hex[:10]}"
    note_item = {
        "user_id": req.user_id,
        "note_id": note_id,
        "title": processed.get("title") or req.title or "Untitled Note",
        "subject": processed.get("subject") or req.subject or "Unknown",
        "raw_text": req.text[:2000],    # Store first 2000 chars as preview
        "summary": processed.get("summary", ""),
        "key_concepts": processed.get("key_concepts", []),
        "mindmap": processed.get("mindmap", {}),
        "formula_list": processed.get("formula_list", []),
        "created_at": now,
        "word_count": len(req.text.split()),
    }
    notes_table.put_item(Item=note_item)

    # Auto-add any tasks found in notes to task board
    created_tasks = []
    for task in processed.get("tasks", []):
        task_id = f"task_{uuid.uuid4().hex[:8]}"
        task_item = {
            "user_id": req.user_id,
            "task_id": task_id,
            "title": task.get("task", ""),
            "deadline": task.get("deadline"),
            "priority": task.get("priority", 3),
            "status": "todo",
            "source": "notes",
            "source_note_id": note_id,
            "created_at": now,
        }
        task_table.put_item(Item=task_item)
        created_tasks.append(task_item)

    return {
        "note_id": note_id,
        "processed": {
            "title": note_item["title"],
            "subject": note_item["subject"],
            "summary": note_item["summary"],
            "key_concepts": note_item["key_concepts"],
            "mindmap": note_item["mindmap"],
            "formula_list": note_item["formula_list"],
        },
        "tasks_extracted": len(created_tasks),
        "tasks": created_tasks,
    }


@router.get("/list/{user_id}")
async def list_notes(user_id: str, subject: Optional[str] = None):
    """
    Returns all notes for a user, optionally filtered by subject.
    """
    table = get_table("notes")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    notes = response.get("Items", [])
    if subject:
        notes = [n for n in notes if subject.lower() in n.get("subject", "").lower()]

    notes.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return {"notes": notes, "total": len(notes)}


@router.get("/{user_id}/{note_id}")
async def get_note(user_id: str, note_id: str):
    """
    Returns a single note with full mindmap and key concepts.
    """
    table = get_table("notes")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(user_id),
    )
    note = next((n for n in response.get("Items", []) if n.get("note_id") == note_id), None)
    if not note:
        raise HTTPException(status_code=404, detail="Note not found")
    return note


@router.post("/ask")
async def ask_about_notes(req: NotesQARequest):
    """
    Student asks a question; Claude answers from their stored notes.
    This is your existing knowledge-graph project, now accessible via chat.
    """
    table = get_table("notes")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    all_notes = response.get("Items", [])

    if req.subject_filter:
        relevant_notes = [
            n for n in all_notes
            if req.subject_filter.lower() in n.get("subject", "").lower()
        ]
    else:
        # Use all notes — Claude will determine which are relevant
        relevant_notes = all_notes

    if not relevant_notes:
        return {
            "answer": "I don't have any notes for this subject yet. Upload your lecture notes first.",
            "sources": [],
        }

    answer = ask_notes(req.question, relevant_notes[:5])

    return {
        "answer": answer,
        "question": req.question,
        "notes_searched": len(relevant_notes),
        "sources": [
            {"note_id": n.get("note_id"), "title": n.get("title"), "subject": n.get("subject")}
            for n in relevant_notes[:5]
        ],
    }


@router.delete("/{user_id}/{note_id}")
async def delete_note(user_id: str, note_id: str):
    """
    Deletes a note.
    """
    table = get_table("notes")
    table.delete_item(Key={"user_id": user_id, "note_id": note_id})
    return {"deleted": True}