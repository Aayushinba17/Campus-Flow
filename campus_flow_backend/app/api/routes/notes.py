from fastapi import APIRouter, UploadFile, File, HTTPException
from pydantic import BaseModel
from typing import List, Optional
import uuid
import json
from datetime import datetime
from boto3.dynamodb.conditions import Key

from app.core.database import get_table
from app.services.claude_service import process_notes, ask_notes
from app.services.aws_service import upload_to_s3
from app.services.embedding_service import embed, cosine_sim

router = APIRouter()

def is_duplicate_task(task_table, user_id: str, new_title: str, threshold: float = 0.82) -> bool:
    """True if a semantically similar task already exists for this user."""
    new_vec = embed(new_title)
    if not new_vec:
        return False
    resp = task_table.query(KeyConditionExpression=Key("user_id").eq(user_id))
    for t in resp.get("Items", []):
        emb = t.get("embedding")
        if emb and cosine_sim(new_vec, json.loads(emb)) >= threshold:
            return True
    return False
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

class SemanticSearchRequest(BaseModel):
    user_id: str
    query: str
    top_k: int = 5


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
    # _embed_text = f"{note_item['title']} {note_item['summary']} {' '.join(note_item['key_concepts'])}"
    # note_item["embedding"] = json.dumps(embed(_embed_text))
    # Build a semantic embedding from summary + key concepts, stored as JSON
    # (DynamoDB rejects raw floats, so we serialize to a string)
    embed_source = (
        (processed.get("summary", "") or "")
        + " "
        + " ".join(processed.get("key_concepts", []) or [])
    ).strip()
    try:
        note_item["embedding"] = json.dumps(embed(embed_source)) if embed_source else None
    except Exception as e:
        print(f"[Notes] Embedding failed: {e}")
        note_item["embedding"] = None
    notes_table.put_item(Item=note_item)

    # Auto-add any tasks found in notes to task board
    created_tasks = []
    for task in processed.get("tasks", []):
    title = task.get("task", "")
    if is_duplicate_task(task_table, req.user_id, title):
        continue
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
        task_item["embedding"] = json.dumps(embed(task.get("task", "")))
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

@router.post("/semantic-search")
async def semantic_search_notes(req: SemanticSearchRequest):
    """
    Finds notes by *meaning*, not keywords. Embeds the query, scores every
    stored note embedding by cosine similarity, returns the closest matches.
    """
    table = get_table("notes")
    response = table.query(
        KeyConditionExpression=Key("user_id").eq(req.user_id),
    )
    notes = response.get("Items", [])
    if not notes:
        return {"results": [], "total": 0, "query": req.query}

    query_vec = embed(req.query)
    scored = []
    for n in notes:
        raw = n.get("embedding")
        if not raw:
            continue
        try:
            vec = json.loads(raw)
        except Exception:
            continue
        scored.append((n, cosine_sim(query_vec, vec)))

    scored.sort(key=lambda x: x[1], reverse=True)
    results = [
        {
            "note_id": n.get("note_id"),
            "title": n.get("title"),
            "subject": n.get("subject"),
            "summary": n.get("summary"),
            "score": round(float(score), 3),
        }
        for n, score in scored[: req.top_k]
        if score > 0.2
    ]
    return {"results": results, "total": len(results), "query": req.query}

@router.post("/reembed/{user_id}")
async def reembed_notes(user_id: str):
    """One-time: compute embeddings for notes saved before semantic search existed."""
    table = get_table("notes")
    response = table.query(KeyConditionExpression=Key("user_id").eq(user_id))
    updated = 0
    for n in response.get("Items", []):
        if n.get("embedding"):
            continue
        src = ((n.get("summary", "") or "") + " " + " ".join(n.get("key_concepts", []) or [])).strip()
        if not src:
            continue
        table.update_item(
            Key={"user_id": user_id, "note_id": n["note_id"]},
            UpdateExpression="SET embedding = :e",
            ExpressionAttributeValues={":e": json.dumps(embed(src))},
        )
        updated += 1
    return {"reembedded": updated}

@router.delete("/{user_id}/{note_id}")
async def delete_note(user_id: str, note_id: str):
    """
    Deletes a note.
    """
    table = get_table("notes")
    table.delete_item(Key={"user_id": user_id, "note_id": note_id})
    return {"deleted": True}