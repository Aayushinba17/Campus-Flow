import json
import anthropic
from app.core.config import settings

_client = None

def get_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        _client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY)
    return _client


# ── Shared context builder ───────────────────────────────────────────────────

def build_student_context(schedule: list, tasks: list, notifications: list, profile: dict) -> str:
    return f"""
Student profile: {json.dumps(profile)}
Current timetable (JSON): {json.dumps(schedule)}
Pending tasks/deadlines: {json.dumps(tasks)}
Recent notifications (last 48h): {json.dumps(notifications[:50])}
Current datetime: {__import__('datetime').datetime.now().isoformat()}
""".strip()


# ── 1. Timetable OCR parser ──────────────────────────────────────────────────

def parse_timetable_text(raw_ocr_text: str) -> dict:
    """
    Takes raw OCR output from AWS Rekognition and returns structured timetable JSON.
    """
    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=2000,
        system="""You are a timetable parser. Extract class schedules from raw OCR text.
Return ONLY valid JSON, no markdown, no explanation.
Format: {"classes": [{"day": "Monday", "start_time": "09:00", "end_time": "10:00",
"subject": "Physics", "room": "B-204", "professor": "Prof. Sharma"}]}
If a field is unknown, use null. Days must be full names: Monday/Tuesday/etc.""",
        messages=[{"role": "user", "content": f"Parse this timetable OCR text:\n\n{raw_ocr_text}"}]
    )
    raw = response.content[0].text.strip()
    # Strip any accidental markdown fences
    raw = raw.replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 2. Notification classifier & deadline extractor ──────────────────────────

def classify_notifications(notifications: list) -> dict:
    """
    Takes a batch of raw notifications, classifies urgency, extracts deadlines.
    Returns structured dict ready for DynamoDB storage.
    """
    client = get_client()
    notif_text = "\n".join([
        f"[{n.get('app', 'unknown')}] {n.get('title', '')} | {n.get('body', '')}"
        for n in notifications
    ])
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=3000,
        system="""You are a notification classifier for a student assistant app.
Return ONLY valid JSON, no markdown.
Format:
{
  "classified": [
    {
      "id": "original_id_from_input",
      "category": "academic|social|promotional|system",
      "priority": 1-5,
      "sender_type": "professor|classmate|family|service|unknown",
      "is_deadline": true/false,
      "deadline_task": "task name if deadline",
      "deadline_date": "YYYY-MM-DD or null",
      "deadline_confidence": 0.0-1.0,
      "summary": "one line summary"
    }
  ],
  "urgent_count": N,
  "deadlines_found": N
}
Priority: 5=extremely urgent, 1=promotional/irrelevant.
Set is_deadline=true if message mentions submission, due date, exam, assignment deadline.""",
        messages=[{
            "role": "user",
            "content": f"Classify these {len(notifications)} notifications:\n\n{notif_text}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 3. Daily morning digest ───────────────────────────────────────────────────

def generate_morning_digest(student_context: str, notifications: list) -> dict:
    """
    Generates the 8AM morning briefing card.
    """
    client = get_client()
    notif_summary = "\n".join([
        f"- [{n.get('category','?')}|P{n.get('priority',1)}] {n.get('summary','')}"
        for n in notifications
    ])
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=1000,
        system="""You are a student's morning briefing assistant. Be concise, warm, and actionable.
Return ONLY valid JSON:
{
  "greeting": "Good morning [name]! One sentence energy-setter.",
  "urgent_items": ["item1", "item2"],
  "todays_classes": ["class summary"],
  "deadlines_today": ["deadline1"],
  "deadlines_this_week": ["deadline2"],
  "social_summary": "one sentence on social messages",
  "wellness_tip": "one short tip for today"
}""",
        messages=[{
            "role": "user",
            "content": f"Student context:\n{student_context}\n\nNotifications from last 8 hours:\n{notif_summary}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 4. Smart reminder enhancer ────────────────────────────────────────────────

def enhance_reminder(class_info: dict, recent_notifications: list) -> str:
    """
    Adds context to a class reminder based on recent relevant messages.
    Returns a single enhanced reminder string.
    """
    client = get_client()
    relevant = [
        n for n in recent_notifications
        if class_info.get("subject", "").lower() in n.get("summary", "").lower()
    ][:5]

    if not relevant:
        return f"{class_info['subject']} in 30 minutes — Room {class_info.get('room', 'TBD')}"

    msgs = "\n".join([f"- {n.get('summary','')}" for n in relevant])
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=150,
        system="You write short (max 25 words), helpful class reminders. Include relevant context from messages. No hashtags, no emoji.",
        messages=[{
            "role": "user",
            "content": f"Class: {class_info['subject']} in 30 min, Room {class_info.get('room','TBD')}\nRecent messages:\n{msgs}\nWrite the reminder:"
        }]
    )
    return response.content[0].text.strip()


# ── 5. Campus Q&A chat ────────────────────────────────────────────────────────

def campus_chat(user_message: str, student_context: str, chat_history: list) -> str:
    """
    Conversational assistant with full student context.
    """
    client = get_client()
    messages = chat_history[-10:] + [{"role": "user", "content": user_message}]
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=800,
        system=f"""You are CampusFlow, a smart personal assistant for a student.
You have access to their real schedule, tasks, and recent messages.
Answer concisely. For schedule/deadline questions, use the data provided.
For calculations (days until exam, free hours), compute exactly.
Never make up information — say 'I don't see that in your data' if uncertain.

{student_context}""",
        messages=messages
    )
    return response.content[0].text.strip()


# ── 6. Notes processor ────────────────────────────────────────────────────────

def process_notes(notes_text: str, subject: str = None) -> dict:
    """
    Takes lecture notes → returns mindmap JSON + extracted tasks + key concepts.
    """
    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=3000,
        system="""You are a notes processor for a student. Extract structured information.
Return ONLY valid JSON:
{
  "subject": "detected or provided subject",
  "title": "lecture title/topic",
  "key_concepts": ["concept1", "concept2"],
  "mindmap": {
    "root": "main topic",
    "branches": [
      {"label": "subtopic", "children": ["detail1", "detail2"]}
    ]
  },
  "tasks": [
    {"task": "task description", "deadline": "YYYY-MM-DD or null", "priority": 1-5}
  ],
  "formula_list": ["formula1 if any"],
  "summary": "3-4 sentence summary of the lecture"
}""",
        messages=[{
            "role": "user",
            "content": f"Subject: {subject or 'auto-detect'}\n\nNotes:\n{notes_text}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 7. Notes Q&A ──────────────────────────────────────────────────────────────

def ask_notes(question: str, notes_context: list) -> str:
    """
    Answers questions based on stored notes content.
    """
    client = get_client()
    notes_text = "\n\n---\n\n".join([
        f"[{n.get('subject','?')} | {n.get('title','?')}]\n{n.get('summary','')}\nKey: {', '.join(n.get('key_concepts',[]))}"
        for n in notes_context[:5]
    ])
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=600,
        system="You answer student questions based strictly on their uploaded notes. Cite which note/subject the answer comes from. If not in notes, say so clearly.",
        messages=[{
            "role": "user",
            "content": f"Notes available:\n{notes_text}\n\nQuestion: {question}"
        }]
    )
    return response.content[0].text.strip()


# ── 8. Routine insights generator ─────────────────────────────────────────────

def generate_routine_insights(usage_logs: list, schedule: list) -> dict:
    """
    Analyzes 7 days of app usage + notification logs to generate routine insights.
    """
    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=1000,
        system="""You analyze student phone usage patterns. Return ONLY valid JSON:
{
  "insights": [
    {"title": "short title", "description": "2 sentences", "type": "study|social|sleep|focus"}
  ],
  "peak_study_hours": ["HH:00-HH:00"],
  "most_distracted_period": "description",
  "recommended_study_slots": ["Day HH:00-HH:00"],
  "weekly_summary": "2-3 sentence overall summary"
}""",
        messages=[{
            "role": "user",
            "content": f"7-day usage logs:\n{json.dumps(usage_logs[:200])}\n\nClass schedule:\n{json.dumps(schedule)}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 9. Exam readiness checklist ───────────────────────────────────────────────

def generate_exam_checklist(exam_info: dict, available_notes: list) -> dict:
    """
    Given an upcoming exam and notes, generates a prep checklist.
    """
    client = get_client()
    note_titles = [f"{n.get('title','?')} ({n.get('subject','?')})" for n in available_notes]
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=800,
        system="""Generate an exam preparation checklist. Return ONLY valid JSON:
{
  "exam_name": "name",
  "days_remaining": N,
  "readiness_score": 0-100,
  "checklist": [
    {"item": "description", "done": false, "priority": "high|medium|low"}
  ],
  "missing_notes_warning": "message if notes seem incomplete",
  "study_plan": "brief 2-3 sentence study plan"
}""",
        messages=[{
            "role": "user",
            "content": f"Exam: {json.dumps(exam_info)}\nAvailable notes: {note_titles}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 10. Stress density analyzer ───────────────────────────────────────────────

def analyze_stress_density(schedule_48h: list, deadlines_48h: list, urgent_notifications: int) -> dict:
    """
    Calculates stress load and generates a wellness message.
    Pure logic with Claude-written human response.
    """
    # Deterministic score — no AI needed for the math
    score = (len(schedule_48h) * 1) + (len(deadlines_48h) * 3) + (urgent_notifications * 2)

    if score < 5:
        level = "light"
    elif score < 12:
        level = "moderate"
    elif score < 20:
        level = "heavy"
    else:
        level = "very_heavy"

    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=100,
        system="Write a single warm, non-judgmental 1-sentence wellness message for a student. No advice, just acknowledgment. Max 20 words.",
        messages=[{
            "role": "user",
            "content": f"Stress level: {level}. Classes: {len(schedule_48h)}, Deadlines: {len(deadlines_48h)}, Urgent messages: {urgent_notifications}"
        }]
    )
    return {
        "score": score,
        "level": level,
        "message": response.content[0].text.strip(),
        "show_alert": score >= 12
    }


# ── 11. Voice note task extractor ─────────────────────────────────────────────

def extract_tasks_from_voice(transcribed_text: str) -> dict:
    """
    Extracts structured tasks from voice memo transcription.
    """
    client = get_client()
    response = client.messages.create(
        model=settings.CLAUDE_MODEL,
        max_tokens=600,
        system="""Extract tasks from spoken text. Return ONLY valid JSON:
{
  "tasks": [
    {
      "task": "clear task description",
      "deadline": "YYYY-MM-DD or null",
      "deadline_text": "original deadline mention",
      "type": "assignment|reminder|follow_up|other",
      "priority": 1-5
    }
  ],
  "raw_summary": "one sentence summary of what was said"
}""",
        messages=[{"role": "user", "content": f"Extract tasks from: \"{transcribed_text}\""}]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)