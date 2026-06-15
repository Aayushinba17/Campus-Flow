import json
from app.core.config import settings
from app.services.embedding_service import embed, cosine_sim

_client = None

class GeminiMessageContent:
    def __init__(self, text):
        self.text = text

class GeminiResponse:
    def __init__(self, text):
        self.content = [GeminiMessageContent(text)]

class GeminiMessages:
    def create(self, model, max_tokens, system, messages):
        from google import genai
        from google.genai import types

        client = genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options=types.HttpOptions(api_version="v1"),
        )

        contents = []
        for m in messages:
            content = m["content"] if m["content"] else " "
            role = "user" if m["role"] == "user" else "model"
            contents.append({"role": role, "parts": [{"text": content}]})

        response = client.models.generate_content(
            model="gemini-1.5-flash",
            config=types.GenerateContentConfig(system_instruction=system),
            contents=contents,
        )
        text = response.text or "No response generated."
        return GeminiResponse(text)

class GeminiClient:
    def __init__(self):
        self.messages = GeminiMessages()

def get_client():
    """
    Returns a Gemini client wrapper.
    """
    global _client
    if _client is None:
        _client = GeminiClient()
    return _client

def get_model() -> str:
    """Returns the correct model ID."""
    return "gemini-1.5-flash"


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
        model=get_model(),
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

def match_messages_to_class(subject: str, professor: str, notifications: list,
                            threshold: float = 0.35, top_k: int = 3) -> list:
    """Return notifications semantically related to a class (subject + professor)."""
    query_vec = embed(f"{subject} {professor or ''}")
    if not query_vec:
        return []
    scored = []
    for n in notifications:
        emb = n.get("embedding")
        nvec = json.loads(emb) if emb else embed(f"{n.get('title','')} {n.get('body','')}")
        s = cosine_sim(query_vec, nvec)
        if s >= threshold:
            scored.append((s, n))
    scored.sort(key=lambda x: x[0], reverse=True)
    return [n for _, n in scored[:top_k]]


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
        model=get_model(),
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
        model=get_model(),
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
    # ✅ FIXED — semantic match
    subject = class_info.get("subject", "")
    relevant = []
    if subject:
        try:
            subject_vec = embed(subject)
            for n in recent_notifications:
                text = n.get("summary") or n.get("body") or n.get("title") or ""
                if text and cosine_sim(subject_vec, embed(text)) > 0.45:
                    relevant.append(n)
        except Exception:
            relevant = [
                n for n in recent_notifications
                if subject.lower() in n.get("summary", "").lower()
            ]
    relevant = relevant[:5]

    if not relevant:
        return f"{class_info['subject']} in 30 minutes — Room {class_info.get('room', 'TBD')}"

    msgs = "\n".join([f"- {n.get('summary','')}" for n in relevant])
    response = client.messages.create(
        model=get_model(),
        max_tokens=150,
        system="You write short (max 25 words), helpful class reminders. Include relevant context from messages. No hashtags, no emoji.",
        messages=[{
            "role": "user",
            "content": f"Class: {class_info['subject']} in 30 min, Room {class_info.get('room','TBD')}\nRecent messages:\n{msgs}\nWrite the reminder:"
        }]
    )
    return response.content[0].text.strip()


# ── 5. Campus Q&A chat (ENHANCED — Instant Q&A) ──────────────────────────────

def campus_chat(user_message: str, student_context: str, chat_history: list) -> str:
    """
    ENHANCED conversational assistant that handles 4 types of queries:
    1. Schedule & task queries — "What do I have tomorrow?" / "Am I free on Friday at 3?"
    2. Notes Q&A — "What were the main points from chemistry?" (uses notes context)
    3. Message context queries — "Did Prof. Singh send anything about the assignment?"
    4. Exam & study planner — "How many days until my DSA exam?" / "How much study time left?"
    """
    client = get_client()
    messages = chat_history[-10:] + [{"role": "user", "content": user_message}]
    response = client.messages.create(
        model=get_model(),
        max_tokens=1200,
        system=f"""You are CampusFlow, a smart personal assistant who ACTUALLY KNOWS the student's life.
You have their real schedule, real tasks, real messages, and real notes loaded into your context.
You feel like talking to a personal assistant who genuinely knows your daily life.

CAPABILITIES — respond based on query type:

1. SCHEDULE & TASK QUERIES
   Questions like: "What do I have tomorrow?", "Am I free on Friday at 3?", "What's due this week?"
   → Look at the schedule and tasks data. Answer with EXACT times, rooms, professors.
   → For "am I free" questions: check all classes and events for that time slot, respond with yes/no + what's around it.
   → For "what's due" questions: list tasks sorted by deadline with days remaining.

2. NOTES Q&A (if notes are in context)
   Questions like: "What were the main points from chemistry?", "Explain the concept in slide 3"
   → Answer STRICTLY from the student's uploaded notes data.
   → Cite which note/subject/lecture the answer comes from.
   → If the answer isn't in their notes, say "I don't see that in your notes — try uploading the relevant lecture."

3. MESSAGE CONTEXT QUERIES
   Questions like: "Did Prof. Singh send anything about the assignment?", "What did my group chat say about the submission?"
   → Search through the recent notifications data for matching messages.
   → Look for the person's name, subject, or keywords in notification titles, bodies, and summaries.
   → Quote the relevant messages you find. If nothing matches, say so.

4. EXAM & STUDY PLANNER
   Questions like: "How many days until my DSA exam?", "How much study time do I have left this week?"
   → CALCULATE precisely from the data. Use the current datetime.
   → For study time: count free slots between now and the exam/deadline.
   → For countdowns: compute exact days and hours remaining.

RULES:
- Be concise but helpful. No fluff.
- NEVER make up information. Only use data from the context provided.
- For calculations, show your work briefly (e.g. "Your DSA exam is on June 20 → that's 7 days from now")
- If you find relevant notifications/messages, quote them directly
- Use the current datetime for any time-based calculations
- Respond conversationally — you're a friend who happens to have perfect memory

CURRENT STUDENT CONTEXT:
{student_context}""",
        messages=messages,
    )
    return response.content[0].text.strip()


# ── 6. Notes processor ────────────────────────────────────────────────────────

def process_notes(notes_text: str, subject: str = None) -> dict:
    """
    Takes lecture notes → returns mindmap JSON + extracted tasks + key concepts.
    """
    client = get_client()
    response = client.messages.create(
        model=get_model(),
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
        model=get_model(),
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
        model=get_model(),
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
        model=get_model(),
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
        model=get_model(),
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
    ENHANCED voice note to task converter.
    
    Student records a 30-second voice memo — e.g.:
    'remind me to submit the physics assignment by Thursday and ask sir about
    the lab practical.'
    
    This extracts:
    - 1 task with deadline: "Submit physics assignment" (deadline: Thursday)
    - 1 follow-up item: "Ask sir about the lab practical" (type: follow_up)
    
    Both get added to the task board. Zero typing required.
    
    App flow: Android SpeechRecognizer → text string → this function → DynamoDB
    """
    client = get_client()
    response = client.messages.create(
        model=get_model(),
        max_tokens=800,
        system=f"""Extract tasks AND follow-up items from a student's spoken voice note.

Return ONLY valid JSON:
{{
  "tasks": [
    {{
      "task": "clear, actionable task description",
      "deadline": "YYYY-MM-DD or null",
      "deadline_text": "original deadline mention from speech (e.g. 'by Thursday')",
      "type": "assignment|reminder|follow_up|meeting|other",
      "priority": 1-5,
      "is_follow_up": false
    }}
  ],
  "follow_ups": [
    {{
      "task": "follow-up action description",
      "context": "why this needs to be done (from speech context)",
      "person": "person to follow up with (if mentioned)",
      "type": "follow_up",
      "priority": 3,
      "is_follow_up": true
    }}
  ],
  "raw_summary": "one sentence summary of everything the student said",
  "total_items": N
}}

Current date: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %A')}

Rules:
- Convert relative dates to absolute: "by Thursday" → next Thursday's YYYY-MM-DD
- Separate tasks (things with deadlines or actions) from follow-ups (things to ask/check/confirm)
- "ask", "check with", "confirm", "follow up", "remind me to ask" → follow_up type
- "submit", "complete", "finish", "send", "write" → assignment/task type
- Keep task descriptions concise but complete
- Priority: urgent/today=5, this week=4, next week=3, no urgency=2, sometime=1
- If the voice note is unclear, extract what you can and note uncertainty""",
        messages=[{"role": "user", "content": f"Extract tasks from this voice note: \"{transcribed_text}\""}]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 12. Missed call context summariser ────────────────────────────────────────

def generate_missed_call_context(caller_name: str, missed_at: str, follow_up_messages: list) -> dict:
    """
    Takes a missed call event + any follow-up messages from the same contact
    within a 30-min window and produces a single context-aware summary.
    e.g. "Missed call from Mom — she then texted asking about dinner."
    """
    client = get_client()

    if not follow_up_messages:
        return {
            "has_follow_up": False,
            "context_summary": f"Missed call from {caller_name} at {missed_at}. No follow-up messages found.",
            "action_needed": False,
        }

    msgs_text = "\n".join([
        f"- [{m.get('app', 'unknown')}] {m.get('title', '')} | {m.get('body', '')}"
        for m in follow_up_messages
    ])

    response = client.messages.create(
        model=get_model(),
        max_tokens=400,
        system="""You combine a missed phone call with follow-up messages from the same person
into a single contextual card for a student.

Return ONLY valid JSON:
{
  "context_summary": "One sentence like: Missed call from Mom — she then texted asking about dinner.",
  "action_needed": true/false,
  "suggested_action": "Call back / Reply to text / No action needed",
  "urgency": "high|medium|low",
  "follow_up_summary": "Brief summary of all follow-up messages"
}

Be concise. Max 30 words for context_summary. Think about what a busy student needs to see.""",
        messages=[{
            "role": "user",
            "content": f"Missed call from: {caller_name}\nMissed at: {missed_at}\n\nFollow-up messages within 30 minutes:\n{msgs_text}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    result = json.loads(raw)
    result["has_follow_up"] = True
    return result


# ── 13. Dedicated deadline extractor ──────────────────────────────────────────

def extract_deadlines_batch(notifications: list) -> dict:
    """
    Dedicated deadline extraction from a batch of notifications.
    Separated from classify_notifications so it can be run independently
    on any set of stored notifications (e.g. re-scan old notifications).

    Returns only deadline-relevant items with confidence scores.
    """
    client = get_client()

    if not notifications:
        return {"deadlines": [], "total_scanned": 0}

    notif_text = "\n".join([
        f"[{n.get('app', n.get('app_name', 'unknown'))}] "
        f"{n.get('title', '')} | {n.get('body', '')} "
        f"(received: {n.get('timestamp', 'unknown')})"
        for n in notifications
    ])

    response = client.messages.create(
        model=get_model(),
        max_tokens=2000,
        system="""You are a deadline extraction engine for a student assistant.
Scan messages for ANY mention of:
- Assignment/homework due dates
- Exam dates and times
- Project submission deadlines
- Registration deadlines
- Meeting times that imply preparation needed
- Event RSVPs with deadlines

Return ONLY valid JSON:
{
  "deadlines": [
    {
      "task": "Clear description of the deadline/task",
      "deadline_date": "YYYY-MM-DD",
      "deadline_time": "HH:MM or null",
      "source_app": "app name where this was found",
      "source_message_preview": "first 50 chars of the source message",
      "confidence": 0.0-1.0,
      "category": "assignment|exam|project|registration|meeting|other",
      "urgency": "high|medium|low"
    }
  ],
  "total_scanned": N
}

Rules:
- Only include items with confidence >= 0.5
- If a date is relative ("tomorrow", "next Monday"), convert to absolute YYYY-MM-DD using current context
- If no year is specified, assume current year
- Set urgency=high if deadline is within 48 hours
- Ignore promotional content, social plans without deadlines""",
        messages=[{
            "role": "user",
            "content": (
                f"Current date: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %A')}\n\n"
                f"Scan these {len(notifications)} notifications for deadlines:\n\n{notif_text}"
            )
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 14. Free slot task suggester ──────────────────────────────────────────────

def suggest_free_slot_tasks(free_slots: list, pending_tasks: list, schedule_context: list) -> dict:
    """
    Given free time gaps in today's schedule and pending tasks,
    suggests what the student should work on during each gap.
    e.g. "You have a 2-hour free gap on Thursday — You have an assignment due Friday,
    this gap is ideal. Add it?"
    """
    client = get_client()

    if not free_slots:
        return {"suggestions": [], "message": "No free slots found today."}

    if not pending_tasks:
        return {"suggestions": [], "message": "No pending tasks to schedule."}

    response = client.messages.create(
        model=get_model(),
        max_tokens=1500,
        system="""You are a smart scheduling assistant for a student.
Given free time slots in their day and their pending tasks/deadlines, suggest
what they should work on during each free slot.

Return ONLY valid JSON:
{
  "suggestions": [
    {
      "slot_start": "HH:MM",
      "slot_end": "HH:MM",
      "slot_duration_minutes": N,
      "suggested_task": "task title",
      "task_id": "original task_id if available",
      "reason": "Why this task fits this slot (max 20 words)",
      "urgency": "high|medium|low",
      "estimated_work_minutes": N,
      "fits_in_slot": true/false
    }
  ],
  "overall_advice": "One sentence productivity tip for today"
}

Rules:
- Prioritize tasks by deadline proximity (closest first)
- If a task needs more time than the slot, suggest starting it
- Don't suggest more than one task per slot
- If a slot is very short (<30 min), suggest review/reading tasks
- Match task complexity to slot duration""",
        messages=[{
            "role": "user",
            "content": (
                f"Current date/time: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %A %H:%M')}\n\n"
                f"Free slots today:\n{json.dumps(free_slots)}\n\n"
                f"Pending tasks:\n{json.dumps(pending_tasks[:20])}\n\n"
                f"Today's schedule context:\n{json.dumps(schedule_context[:10])}"
            )
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 15. Booking & event detector from messages ────────────────────────────────

def detect_booking_events(notifications: list) -> dict:
    """
    Scans notifications for event mentions: train/flight bookings, movie tickets,
    interviews, doctor appointments, etc. Returns structured events with
    travel time estimates that can be auto-added to the schedule.
    """
    client = get_client()

    if not notifications:
        return {"events": [], "total_scanned": 0}

    notif_text = "\n".join([
        f"[{n.get('app', n.get('app_name', 'unknown'))}] "
        f"{n.get('title', '')} | {n.get('body', '')}"
        for n in notifications
    ])

    response = client.messages.create(
        model=get_model(),
        max_tokens=2000,
        system="""You detect real-world events and bookings from a student's messages.

Look for:
- Train/flight/bus bookings (IRCTC, MakeMyTrip, RedBus, airline confirmations)
- Movie/show tickets (BookMyShow, PVR)
- Interview/placement calls (company names, HR messages)
- Doctor/dentist appointments
- Any message that implies the student needs to BE somewhere at a specific time

Return ONLY valid JSON:
{
  "events": [
    {
      "title": "Event title (e.g. 'Train to Delhi', 'Interview at TCS')",
      "event_type": "travel|entertainment|interview|medical|meeting|other",
      "date": "YYYY-MM-DD",
      "time": "HH:MM",
      "end_time": "HH:MM or null",
      "location": "venue/station/address or null",
      "source_app": "app name",
      "source_preview": "first 40 chars of source message",
      "travel_time_minutes": N,
      "reminder_minutes_before": N,
      "booking_reference": "PNR/booking ID if found, else null",
      "confidence": 0.0-1.0
    }
  ],
  "total_scanned": N
}

Rules:
- Only include events with confidence >= 0.6
- Estimate travel_time_minutes based on event type (train station=60, movie=30, interview=45)
- Set reminder_minutes_before = travel_time + 30 (preparation buffer)
- Convert relative dates to absolute using current date context
- Ignore promotional offers — only actual confirmed bookings/appointments""",
        messages=[{
            "role": "user",
            "content": (
                f"Current date: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %A')}\n\n"
                f"Scan these {len(notifications)} messages for events/bookings:\n\n{notif_text}"
            )
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 16. Exam prep countdown with study slot blocking ──────────────────────────

def generate_exam_countdown(exam_info: dict, schedule: list, existing_tasks: list) -> dict:
    """
    Once an exam date is detected (from messages or manual entry), generates:
    1. A countdown (days/hours remaining)
    2. Auto-blocked study slots in the week before the exam
    3. A day-by-day study plan based on available free time
    """
    client = get_client()
    response = client.messages.create(
        model=get_model(),
        max_tokens=2000,
        system="""You create an exam preparation countdown and study schedule for a student.

Given their exam details, class schedule, and existing tasks, create a day-by-day
study plan that fits around their existing commitments.

Return ONLY valid JSON:
{
  "exam_name": "subject name",
  "exam_date": "YYYY-MM-DD",
  "exam_time": "HH:MM or null",
  "days_remaining": N,
  "hours_remaining": N,
  "urgency_level": "critical|high|medium|comfortable",
  "study_plan": [
    {
      "date": "YYYY-MM-DD",
      "day": "Monday",
      "study_slots": [
        {
          "start": "HH:MM",
          "end": "HH:MM",
          "duration_minutes": N,
          "focus_topic": "What to study in this slot",
          "study_type": "revision|practice|new_material|mock_test"
        }
      ],
      "total_study_minutes": N,
      "daily_goal": "One sentence goal for this day"
    }
  ],
  "total_study_hours_planned": N,
  "revision_tips": ["tip1", "tip2"],
  "confidence_message": "Motivational message based on time available"
}

Rules:
- Block study slots only in free periods (no conflicts with existing classes)
- Morning slots (8-10 AM) for difficult topics, evening (6-9 PM) for revision
- Last day before exam = light revision only, no heavy study
- If < 3 days remaining, mark as critical and plan intensive sessions
- Include at least one break/rest slot per day""",
        messages=[{
            "role": "user",
            "content": (
                f"Current date/time: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %A %H:%M')}\n\n"
                f"Exam: {json.dumps(exam_info)}\n\n"
                f"Weekly class schedule:\n{json.dumps(schedule[:30])}\n\n"
                f"Existing pending tasks:\n{json.dumps(existing_tasks[:15])}"
            )
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 17. Slack / academic email thread summarizer ──────────────────────────────

def summarize_email_thread(messages: list, source_type: str = "email") -> dict:
    """
    Summarizes long email threads or Slack conversations into 2-line updates.
    Flags any action items that require a reply from the student.
    """
    client = get_client()

    if not messages:
        return {"summaries": [], "action_items": []}

    thread_text = "\n".join([
        f"[{m.get('sender', m.get('title', 'unknown'))}] {m.get('body', m.get('content', ''))}"
        for m in messages
    ])

    response = client.messages.create(
        model=get_model(),
        max_tokens=1500,
        system=f"""You summarize {source_type} threads for a busy student.

Return ONLY valid JSON:
{{
  "summaries": [
    {{
      "thread_subject": "Original subject/topic",
      "summary": "2-line summary of the entire thread (max 50 words)",
      "participants": ["name1", "name2"],
      "message_count": N,
      "latest_sender": "who sent the last message",
      "latest_timestamp": "when",
      "category": "academic|administrative|group_project|club|personal",
      "importance": "high|medium|low"
    }}
  ],
  "action_items": [
    {{
      "action": "What the student needs to do",
      "deadline": "YYYY-MM-DD or null",
      "source_thread": "thread subject",
      "requires_reply": true/false,
      "urgency": "high|medium|low"
    }}
  ],
  "total_threads_processed": N,
  "unread_requiring_action": N
}}

Rules:
- Keep summaries to exactly 2 lines (max 50 words each)
- Flag any message that asks a direct question to the student
- Flag any message with deadlines, assignments, or meeting requests
- "requires_reply" = true if someone asked the student something directly
- Group messages by thread/subject when possible""",
        messages=[{
            "role": "user",
            "content": f"Summarize these {source_type} messages:\n\n{thread_text}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 18. Query intent detector ─────────────────────────────────────────────────

def detect_query_intent(user_message: str) -> dict:
    """
    Classifies the student's chat message into one of 4 intent categories
    so the chat router can pre-fetch exactly the right data (instead of dumping
    everything into context and wasting tokens).

    Returns: {intent, entities, needs_notes, needs_notifications, needs_schedule}
    """
    client = get_client()
    response = client.messages.create(
        model=get_model(),
        max_tokens=300,
        system="""Classify this student's question into an intent category.

Return ONLY valid JSON:
{
  "intent": "schedule|notes|messages|exam_study|general",
  "sub_intent": "specific sub-type (e.g. 'free_slot_check', 'deadline_query', 'person_search', 'countdown')",
  "entities": {
    "person_name": "extracted person/professor name or null",
    "subject": "extracted subject/course name or null",
    "date_reference": "extracted date reference ('tomorrow', 'Friday', 'next week') or null",
    "time_reference": "extracted time ('3 PM', 'morning') or null",
    "keyword": "key search term or null"
  },
  "needs_schedule": true/false,
  "needs_tasks": true/false,
  "needs_notifications": true/false,
  "needs_notes": true/false
}

Intent categories:
- "schedule": Questions about classes, free time, what's happening when
- "notes": Questions about lecture content, concepts, study material
- "messages": Questions about who said what, searching notifications
- "exam_study": Questions about exam countdowns, study time, deadlines
- "general": Everything else (greetings, general advice, etc.)""",
        messages=[{"role": "user", "content": user_message}]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {
            "intent": "general",
            "entities": {},
            "needs_schedule": True,
            "needs_tasks": True,
            "needs_notifications": True,
            "needs_notes": False,
        }


# ── 19. Message context search ────────────────────────────────────────────────

def search_notification_context(query: str, notifications: list) -> dict:
    """
    Searches notification history for specific people, topics, or keywords.
    Used when student asks: "Did Prof. Singh send anything about the assignment?"
    or "What did my group chat say about the submission?"

    Returns matching notifications with relevance scoring.
    """
    client = get_client()

    if not notifications:
        return {"matches": [], "answer": "No notifications in history to search.", "total_searched": 0}

    notif_text = "\n".join([
        f"[{i+1}] [{n.get('app', 'unknown')}] {n.get('title', '')} | "
        f"{n.get('body', '')[:200]} (at {n.get('timestamp', n.get('ingested_at', 'unknown'))})"
        for i, n in enumerate(notifications)
    ])

    response = client.messages.create(
        model=get_model(),
        max_tokens=1000,
        system="""You search a student's notification history to answer their question.

Return ONLY valid JSON:
{
  "matches": [
    {
      "index": N,
      "relevance": "high|medium|low",
      "reason": "Why this notification matches the query",
      "key_quote": "The most relevant part of the notification body"
    }
  ],
  "answer": "Direct answer to the student's question based on found messages (2-3 sentences max)",
  "total_searched": N,
  "found_relevant": N
}

Rules:
- Search by person name, subject, keywords, app name
- Include partial matches if they might be relevant
- Sort matches by relevance (high first)
- In the answer, quote specific message content
- If nothing matches, say "I couldn't find any messages about that"
- Maximum 10 matches""",
        messages=[{
            "role": "user",
            "content": f"Student's question: \"{query}\"\n\nSearch these {len(notifications)} notifications:\n\n{notif_text}"
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)


# ── 20. Study time calculator ─────────────────────────────────────────────────

def calculate_study_availability(schedule: list, tasks: list, target_date: str = None) -> dict:
    """
    Computes exact free study hours between now and a target date (exam/deadline).
    Analyzes the weekly schedule to subtract class time and returns available
    study slots with total hours.

    Used for: "How much study time do I have left this week?"
    """
    client = get_client()

    response = client.messages.create(
        model=get_model(),
        max_tokens=1000,
        system="""You calculate a student's available study time from their schedule data.

Return ONLY valid JSON:
{
  "total_free_hours_remaining": N,
  "total_study_hours_recommended": N,
  "days_analyzed": N,
  "daily_breakdown": [
    {
      "date": "YYYY-MM-DD",
      "day": "Monday",
      "free_hours": N,
      "recommended_study_hours": N,
      "free_slots": ["HH:MM-HH:MM", "HH:MM-HH:MM"],
      "busy_with": ["Class1 10-11", "Class2 14-15"]
    }
  ],
  "summary": "You have X hours of free time this week. With Y hours of classes, I'd recommend studying Z hours per day.",
  "productivity_tip": "One actionable tip"
}

Rules:
- Assume productive hours are 8AM to 10PM
- Subtract all classes and known events
- Recommend study hours = 60% of free time (rest for meals, breaks, etc.)
- If target_date is provided, only count up to that date
- If no target_date, analyze the next 7 days""",
        messages=[{
            "role": "user",
            "content": (
                f"Current datetime: {__import__('datetime').datetime.now().strftime('%Y-%m-%d %A %H:%M')}\n"
                f"Target date: {target_date or 'next 7 days'}\n\n"
                f"Weekly schedule:\n{json.dumps(schedule[:30])}\n\n"
                f"Pending tasks/deadlines:\n{json.dumps(tasks[:20])}"
            )
        }]
    )
    raw = response.content[0].text.strip().replace("```json", "").replace("```", "").strip()
    return json.loads(raw)