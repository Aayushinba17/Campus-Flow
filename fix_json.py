import re
import os

with open('campus_flow_backend/app/services/claude_service.py', 'r', encoding='utf-8') as f:
    content = f.read()

# Add safe_json_parse
import_section = """import json
from app.core.config import settings
from app.services.embedding_service import embed, cosine_sim

def safe_json_parse(raw_text: str, fallback: dict = None) -> dict:
    try:
        return json.loads(raw_text)
    except json.JSONDecodeError:
        return fallback or {}
"""
content = content.replace('import json\nfrom app.core.config import settings\nfrom app.services.embedding_service import embed, cosine_sim', import_section)

# Replace json.loads(raw) with safe_json_parse(raw, fallback)
replacements = [
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"classes": []})', 'parse_timetable_text'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"classified": [], "urgent_count": 0, "deadlines_found": 0})', 'classify_notifications'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"greeting": "Good morning!", "urgent_items": [], "todays_classes": [], "deadlines_today": [], "deadlines_this_week": [], "social_summary": "", "wellness_tip": ""})', 'generate_morning_digest'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"subject": "Unknown", "title": "Unknown", "key_concepts": [], "mindmap": {}, "tasks": [], "formula_list": [], "summary": ""})', 'process_notes'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"insights": [], "peak_study_hours": [], "most_distracted_period": "", "recommended_study_slots": [], "weekly_summary": ""})', 'generate_routine_insights'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"exam_name": "Unknown", "days_remaining": 0, "readiness_score": 0, "checklist": [], "missing_notes_warning": "", "study_plan": ""})', 'generate_exam_checklist'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"tasks": [], "follow_ups": [], "raw_summary": "", "total_items": 0})', 'extract_tasks_from_voice'),
    ('result = json.loads(raw)', 'result = safe_json_parse(raw, {"context_summary": "", "action_needed": False, "suggested_action": "", "urgency": "low", "follow_up_summary": ""})', 'generate_missed_call_context'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"deadlines": [], "total_scanned": 0})', 'extract_deadlines_batch'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"suggestions": [], "overall_advice": ""})', 'suggest_free_slot_tasks'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"events": [], "total_scanned": 0})', 'detect_booking_events'),
    ('return json.loads(raw)', 'return safe_json_parse(raw, {"exam_name": "Unknown", "exam_date": "", "days_remaining": 0, "study_plan": []})', 'generate_exam_countdown'),
]

for old, new, func_name in replacements:
    pattern = r'(def ' + func_name + r'.*?)(?=def |$)'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        func_body = match.group(1)
        new_body = func_body.replace(old, new)
        content = content.replace(func_body, new_body)

with open('campus_flow_backend/app/services/claude_service.py', 'w', encoding='utf-8') as f:
    f.write(content)
