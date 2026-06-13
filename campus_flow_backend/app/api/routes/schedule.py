from fastapi import APIRouter, HTTPException, UploadFile, File
from pydantic import BaseModel
from typing import List, Optional
import uuid
from datetime import datetime

from app.core.database import get_table
from app.services.claude_service import parse_timetable_text, generate_exam_checklist
from app.services.aws_service import extract_text_from_image, upload_to_s3

router = APIRouter()


# ── Models ────────────────────────────────────────────────────────────────────

class ClassEntry(BaseModel):
    day: str
    start_time: str
    end_time: str
    subject: str
    room: Optional[str] = None
    professor: Optional[str] = None

class ScheduleResponse(BaseModel):
    user_id: str
    classes: List[ClassEntry]
    parsed_at: str

class ManualEventRequest(BaseModel):
    user_id: str
    title: str
    date: str           # YYYY-MM-DD
    start_time: str     # HH:MM
    end_time: str
    category: str       # class|deadline|exam|personal
    location: Optional[str] = None
    notes: Optional[str] = None

class ExamChecklistRequest(BaseModel):
    user_id: str
    exam_subject: str
    exam_date: str      # YYYY-MM-DD


# ── Routes ────────────────────────────────────────────────────────────────────

@router.post("/upload-image")
async def upload_timetable_image(user_id: str, file: UploadFile = File(...)):
    """
    Step 1: Upload timetable photo.
    Step 2: Rekognition OCR extracts text.
    Step 3: Claude parses into structured JSON.
    Step 4: Save to DynamoDB.
    """
    if file.content_type not in ["image/jpeg", "image/png", "image/jpg"]:
        raise HTTPException(status_code=400, detail="Only JPEG/PNG images accepted")

    image_bytes = await file.read()

    # OCR via Rekognition
    ocr_text = extract_text_from_image(image_bytes)
    if not ocr_text.strip():
        raise HTTPException(status_code=422, detail="No text detected in image. Try a clearer photo.")

    # Upload original to S3 for reference
    s3_key = upload_to_s3(image_bytes, file.filename or "timetable.jpg")

    # Claude parses OCR text into structured schedule
    parsed = parse_timetable_text(ocr_text)

    # Save each class as a separate DynamoDB item
    table = get_table("schedules")
    now = datetime.now().isoformat()
    saved_classes = []

    for cls in parsed.get("classes", []):
        item_id = f"class_{uuid.uuid4().hex[:8]}"
        item = {
            "user_id": user_id,
            "item_id": item_id,
            "type": "class",
            "day": cls.get("day"),
            "start_time": cls.get("start_time"),
            "end_time": cls.get("end_time"),
            "subject": cls.get("subject"),
            "room": cls.get("room"),
            "professor": cls.get("professor"),
            "s3_source": s3_key,
            "created_at": now,
        }
        table.put_item(Item=item)
        saved_classes.append(item)

    return {
        "success": True,
        "ocr_text_preview": ocr_text[:300],
        "classes_parsed": len(saved_classes),
        "classes": saved_classes,
    }


@router.get("/classes/{user_id}")
async def get_schedule(user_id: str):
    """
    Returns all classes for a user.
    """
    table = get_table("schedules")
    response = table.query(
        KeyConditionExpression="user_id = :uid",
        ExpressionAttributeValues={":uid": user_id},
    )
    items = response.get("Items", [])
    classes = [i for i in items if i.get("type") == "class"]
    events = [i for i in items if i.get("type") == "event"]
    return {"classes": classes, "events": events, "total": len(items)}


@router.post("/event")
async def add_manual_event(req: ManualEventRequest):
    """
    Adds a manual event (exam, interview, booking, etc.)
    """
    table = get_table("schedules")
    item_id = f"event_{uuid.uuid4().hex[:8]}"
    item = {
        "user_id": req.user_id,
        "item_id": item_id,
        "type": "event",
        "title": req.title,
        "date": req.date,
        "start_time": req.start_time,
        "end_time": req.end_time,
        "category": req.category,
        "location": req.location,
        "notes": req.notes,
        "created_at": datetime.now().isoformat(),
    }
    table.put_item(Item=item)
    return {"success": True, "event": item}


@router.get("/today/{user_id}")
async def get_today_view(user_id: str):
    """
    Returns unified today view: classes + deadlines for today's date.
    """
    from datetime import date
    today = date.today()
    today_str = today.strftime("%Y-%m-%d")
    today_day = today.strftime("%A")          # "Monday", "Tuesday", etc.

    schedule_table = get_table("schedules")
    task_table = get_table("tasks")

    # Get classes for today's day-of-week
    schedule_resp = schedule_table.query(
        KeyConditionExpression="user_id = :uid",
        ExpressionAttributeValues={":uid": user_id},
    )
    all_items = schedule_resp.get("Items", [])
    todays_classes = [
        i for i in all_items
        if i.get("type") == "class" and i.get("day", "").lower() == today_day.lower()
    ]
    todays_events = [
        i for i in all_items
        if i.get("type") == "event" and i.get("date") == today_str
    ]

    # Get tasks due today or overdue
    task_resp = task_table.query(
        KeyConditionExpression="user_id = :uid",
        ExpressionAttributeValues={":uid": user_id},
    )
    all_tasks = task_resp.get("Items", [])
    due_today = [
        t for t in all_tasks
        if t.get("deadline") == today_str and t.get("status") != "done"
    ]
    overdue = [
        t for t in all_tasks
        if t.get("deadline") and t.get("deadline") < today_str and t.get("status") != "done"
    ]

    return {
        "date": today_str,
        "day": today_day,
        "classes": sorted(todays_classes, key=lambda x: x.get("start_time", "")),
        "events": todays_events,
        "due_today": due_today,
        "overdue": overdue,
        "free_slots": _calculate_free_slots(todays_classes + todays_events),
    }


@router.post("/exam-checklist")
async def get_exam_checklist(req: ExamChecklistRequest):
    """
    Generates AI-powered exam prep checklist based on uploaded notes.
    """
    from datetime import date
    notes_table = get_table("notes")
    response = notes_table.query(
        KeyConditionExpression="user_id = :uid",
        ExpressionAttributeValues={":uid": req.user_id},
    )
    subject_notes = [
        n for n in response.get("Items", [])
        if req.exam_subject.lower() in n.get("subject", "").lower()
    ]

    exam_date = datetime.strptime(req.exam_date, "%Y-%m-%d").date()
    days_remaining = (exam_date - date.today()).days

    checklist = generate_exam_checklist(
        exam_info={"subject": req.exam_subject, "date": req.exam_date, "days_remaining": days_remaining},
        available_notes=subject_notes,
    )
    return checklist


# ── Helpers ───────────────────────────────────────────────────────────────────

def _calculate_free_slots(busy_items: list) -> list:
    """
    Given a list of schedule items with start/end times, returns free slots
    between 8AM and 10PM.
    """
    WORK_START = "08:00"
    WORK_END = "22:00"

    # Convert to minutes-from-midnight for arithmetic
    def to_minutes(t: str) -> int:
        h, m = t.split(":")
        return int(h) * 60 + int(m)

    def to_time(minutes: int) -> str:
        return f"{minutes // 60:02d}:{minutes % 60:02d}"

    busy = []
    for item in busy_items:
        start = item.get("start_time")
        end = item.get("end_time")
        if start and end:
            busy.append((to_minutes(start), to_minutes(end)))

    busy.sort()
    free = []
    cursor = to_minutes(WORK_START)
    end_of_day = to_minutes(WORK_END)

    for start, end in busy:
        if cursor < start:
            duration = start - cursor
            if duration >= 60:                # Only show gaps of 60+ minutes
                free.append({
                    "start": to_time(cursor),
                    "end": to_time(start),
                    "duration_minutes": duration,
                })
        cursor = max(cursor, end)

    if cursor < end_of_day and (end_of_day - cursor) >= 60:
        free.append({
            "start": to_time(cursor),
            "end": to_time(end_of_day),
            "duration_minutes": end_of_day - cursor,
        })

    return free