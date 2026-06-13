import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String _base = AppConstants.baseUrl;
  final String _uid  = AppConstants.userId;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ── Health check ──────────────────────────────────────────────────────

  Future<bool> isServerReachable() async {
    try {
      final r = await http.get(Uri.parse('$_base/health'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) { return false; }
  }

  // ── Schedule ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadTimetableImage(File imageFile) async {
    final uri = Uri.parse('$_base${AppConstants.scheduleUpload}?user_id=$_uid');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getTodayView() async {
    final r = await http.get(
      Uri.parse('$_base${AppConstants.scheduleToday}/$_uid'),
      headers: _headers,
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> getSchedule() async {
    final r = await http.get(
      Uri.parse('$_base${AppConstants.scheduleClasses}/$_uid'),
      headers: _headers,
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> addManualEvent(Map<String, dynamic> event) async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.scheduleEvent}'),
      headers: _headers,
      body: jsonEncode({...event, 'user_id': _uid}),
    );
    return jsonDecode(r.body);
  }

  // ── Notifications ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> ingestNotifications(List<Map<String, dynamic>> notifications) async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.notifIngest}'),
      headers: _headers,
      body: jsonEncode({'user_id': _uid, 'notifications': notifications}),
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> getMorningDigest({int hoursBack = 8}) async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.notifDigest}'),
      headers: _headers,
      body: jsonEncode({'user_id': _uid, 'hours_back': hoursBack}),
    );
    return jsonDecode(r.body);
  }

  Future<List<dynamic>> getRecentNotifications({int hours = 24, int minPriority = 1}) async {
    final r = await http.get(
      Uri.parse('$_base${AppConstants.notifRecent}/$_uid?hours=$hours&min_priority=$minPriority'),
      headers: _headers,
    );
    return jsonDecode(r.body)['notifications'] ?? [];
  }

  Future<List<dynamic>> getExtractedDeadlines({int daysAhead = 7}) async {
    final r = await http.get(
      Uri.parse('$_base${AppConstants.notifDeadlines}/$_uid?days_ahead=$daysAhead'),
      headers: _headers,
    );
    return jsonDecode(r.body)['deadlines'] ?? [];
  }

  // ── Routine ───────────────────────────────────────────────────────────

  Future<void> sendUsageLogs(List<Map<String, dynamic>> entries) async {
    await http.post(
      Uri.parse('$_base${AppConstants.routineUsageLog}'),
      headers: _headers,
      body: jsonEncode({'user_id': _uid, 'entries': entries}),
    );
  }

  Future<Map<String, dynamic>> getUsageHeatmap({int days = 7}) async {
    final r = await http.get(
      Uri.parse('$_base${AppConstants.routineHeatmap}/$_uid?days=$days'),
      headers: _headers,
    );
    return jsonDecode(r.body);
  }

  Future<void> updateActivityContext(Map<String, dynamic> context) async {
    await http.post(
      Uri.parse('$_base${AppConstants.routineContext}'),
      headers: _headers,
      body: jsonEncode({...context, 'user_id': _uid}),
    );
  }

  Future<void> logSleepEvent(String screenOffTime, String screenOnTime, String date) async {
    await http.post(
      Uri.parse('$_base${AppConstants.routineSleepLog}'),
      headers: _headers,
      body: jsonEncode({
        'user_id': _uid,
        'screen_off_time': screenOffTime,
        'screen_on_time': screenOnTime,
        'date': date,
      }),
    );
  }

  Future<Map<String, dynamic>> generateRoutineInsights() async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.routineInsights}/$_uid'),
      headers: _headers,
    );
    return jsonDecode(r.body);
  }

  // ── Tasks ─────────────────────────────────────────────────────────────

  Future<List<dynamic>> getAllTasks({String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final r = await http.get(
      Uri.parse('$_base${AppConstants.tasksBase}/$_uid$query'),
      headers: _headers,
    );
    return jsonDecode(r.body)['tasks'] ?? [];
  }

  Future<void> confirmTask(String taskId) async {
    await http.post(
      Uri.parse('$_base${AppConstants.tasksBase}/$_uid/confirm/$taskId'),
      headers: _headers,
    );
  }

  Future<void> updateTaskStatus(String taskId, String status) async {
    await http.post(
      Uri.parse('$_base${AppConstants.tasksBase}/$_uid/update-status/$taskId?status=$status'),
      headers: _headers,
    );
  }

  // ── Reminders ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStressDensity() async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.remindersStress}'),
      headers: _headers,
      body: jsonEncode({'user_id': _uid}),
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> checkWellnessReminder(String type) async {
    final now = TimeOfDay.now();
    final r = await http.post(
      Uri.parse('$_base${AppConstants.remindersWellness}'),
      headers: _headers,
      body: jsonEncode({
        'user_id': _uid,
        'reminder_type': type,
        'current_time': '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}',
      }),
    );
    return jsonDecode(r.body);
  }

  Future<void> dismissWellnessReminder(String type) async {
    await http.post(
      Uri.parse('$_base${AppConstants.remindersDismiss}?user_id=$_uid&reminder_type=$type'),
      headers: _headers,
    );
  }

  // ── Chat ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendChatMessage(String message, {String? sessionId}) async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.chatMessage}'),
      headers: _headers,
      body: jsonEncode({
        'user_id': _uid,
        'message': message,
        if (sessionId != null) 'session_id': sessionId,
      }),
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> processVoiceNote(String transcribedText) async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.chatVoice}'),
      headers: _headers,
      body: jsonEncode({'user_id': _uid, 'transcribed_text': transcribedText}),
    );
    return jsonDecode(r.body);
  }

  Future<List<dynamic>> getChatHistory() async {
    final r = await http.get(
      Uri.parse('$_base${AppConstants.chatHistory}/$_uid'),
      headers: _headers,
    );
    return jsonDecode(r.body)['history'] ?? [];
  }

  // ── Notes ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> processNoteText(String text, {String? subject}) async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.notesProcess}'),
      headers: _headers,
      body: jsonEncode({
        'user_id': _uid,
        'text': text,
        if (subject != null) 'subject': subject,
      }),
    );
    return jsonDecode(r.body);
  }

  Future<List<dynamic>> getNotesList({String? subject}) async {
    final query = subject != null ? '?subject=$subject' : '';
    final r = await http.get(
      Uri.parse('$_base${AppConstants.notesList}/$_uid$query'),
      headers: _headers,
    );
    return jsonDecode(r.body)['notes'] ?? [];
  }

  Future<Map<String, dynamic>> askNotes(String question, {String? subject}) async {
    final r = await http.post(
      Uri.parse('$_base${AppConstants.notesAsk}'),
      headers: _headers,
      body: jsonEncode({
        'user_id': _uid,
        'question': question,
        if (subject != null) 'subject_filter': subject,
      }),
    );
    return jsonDecode(r.body);
  }

  // ── Wellness ──────────────────────────────────────────────────────────

  Future<void> logPomodoroSession(Map<String, dynamic> session) async {
    await http.post(
      Uri.parse('$_base${AppConstants.wellnessPomodoro}'),
      headers: _headers,
      body: jsonEncode({...session, 'user_id': _uid}),
    );
  }

  Future<Map<String, dynamic>> getWeeklySummary() async {
    final r = await http.get(
      Uri.parse('$_base${AppConstants.wellnessSummary}/$_uid'),
      headers: _headers,
    );
    return jsonDecode(r.body);
  }
}

// Simple TimeOfDay helper (avoid importing flutter/material just for this)
class TimeOfDay {
  final int hour, minute;
  TimeOfDay({required this.hour, required this.minute});
  static TimeOfDay now() {
    final t = DateTime.now();
    return TimeOfDay(hour: t.hour, minute: t.minute);
  }
}