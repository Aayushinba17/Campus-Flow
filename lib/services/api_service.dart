import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../utils/constants.dart';

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

  // ── Generic helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await http.get(Uri.parse('$_base$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      Uri.parse('$_base$path'), headers: _headers, body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
    return jsonDecode(r.body);
  }

  // ── Health check ──────────────────────────────────────────────────────

  Future<bool> isServerReachable() async {
    try {
      final r = await http.get(Uri.parse('$_base/health'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) { return false; }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SCHEDULE
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> uploadTimetableImage(File imageFile) async {
    final uri = Uri.parse('$_base${AppConstants.scheduleUpload}?user_id=$_uid');
    final request = http.MultipartRequest('POST', uri);
    // Explicitly set content type — Android image_picker sometimes sends
    // application/octet-stream which the backend rejects.
    final ext = imageFile.path.split('.').last.toLowerCase();
    request.files.add(await http.MultipartFile.fromPath(
      'file', imageFile.path,
      contentType: MediaType('image', ext == 'png' ? 'png' : 'jpeg'),
    ));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> getTodayView() async =>
      _get('${AppConstants.scheduleToday}/$_uid');

  Future<Map<String, dynamic>> getSchedule() async =>
      _get('${AppConstants.scheduleClasses}/$_uid');

  Future<Map<String, dynamic>> addManualEvent(Map<String, dynamic> event) async =>
      _post(AppConstants.scheduleEvent, {...event, 'user_id': _uid});

  Future<Map<String, dynamic>> getFreeSlotSuggestions(String date) async =>
      _post(AppConstants.scheduleFreeSlots, {'user_id': _uid, 'date': date});

  Future<Map<String, dynamic>> detectBookings(List<Map<String, dynamic>> messages) async =>
      _post(AppConstants.scheduleBookings, {'user_id': _uid, 'messages': messages});

  Future<Map<String, dynamic>> confirmBooking(String itemId) async =>
      _post('${AppConstants.scheduleConfirmBk}/$_uid/$itemId', {});

  Future<Map<String, dynamic>> dismissBooking(String itemId) async {
    final r = await http.delete(
      Uri.parse('$_base${AppConstants.scheduleDismissBk}/$_uid/$itemId'),
      headers: _headers,
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> getExamCountdown(String examName, String examDate, {String? subject}) async =>
      _post(AppConstants.scheduleExamCount, {
        'user_id': _uid, 'exam_name': examName, 'exam_date': examDate,
        if (subject != null) 'subject': subject,
      });

  Future<Map<String, dynamic>> getExamChecklist(String examName, String examDate, {String? subject}) async =>
      _post(AppConstants.scheduleChecklist, {
        'user_id': _uid, 'exam_name': examName, 'exam_date': examDate,
        if (subject != null) 'subject': subject,
      });

  // ═══════════════════════════════════════════════════════════════════════
  //  NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> ingestNotifications(List<Map<String, dynamic>> notifications) async =>
      _post(AppConstants.notifIngest, {'user_id': _uid, 'notifications': notifications});

  Future<Map<String, dynamic>> getMorningDigest({int hoursBack = 8}) async =>
      _post(AppConstants.notifDigest, {'user_id': _uid, 'hours_back': hoursBack});

  Future<List<dynamic>> getRecentNotifications({int hours = 24, int minPriority = 1}) async {
    final r = await _get('${AppConstants.notifRecent}/$_uid?hours=$hours&min_priority=$minPriority');
    return r['notifications'] ?? [];
  }

  Future<List<dynamic>> getExtractedDeadlines({int daysAhead = 7}) async {
    final r = await _get('${AppConstants.notifDeadlines}/$_uid?days_ahead=$daysAhead');
    return r['deadlines'] ?? [];
  }

  Future<Map<String, dynamic>> getMissedCallContext({
    required String callerName, required String missedAt,
    List<Map<String, dynamic>> followUpMessages = const [],
  }) async =>
      _post(AppConstants.notifMissedCall, {
        'user_id': _uid, 'caller_name': callerName, 'missed_at': missedAt,
        'follow_up_messages': followUpMessages,
      });

  Future<List<dynamic>> getMissedCalls() async {
    final r = await _get('${AppConstants.notifMissedCalls}/$_uid');
    return r['missed_calls'] ?? [];
  }

  Future<Map<String, dynamic>> extractDeadlinesFromMessages(List<Map<String, dynamic>> messages) async =>
      _post(AppConstants.notifExtractDead, {'user_id': _uid, 'messages': messages});

  Future<Map<String, dynamic>> getNotificationStats() async =>
      _get('${AppConstants.notifStats}/$_uid');

  // ═══════════════════════════════════════════════════════════════════════
  //  ROUTINE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> sendUsageLogs(List<Map<String, dynamic>> entries) async =>
      _post(AppConstants.routineUsageLog, {'user_id': _uid, 'entries': entries});

  Future<Map<String, dynamic>> getUsageHeatmap({int days = 7}) async =>
      _get('${AppConstants.routineHeatmap}/$_uid?days=$days');

  Future<void> updateActivityContext(Map<String, dynamic> context) async =>
      _post(AppConstants.routineContext, {...context, 'user_id': _uid});

  Future<Map<String, dynamic>> getCurrentContext() async =>
      _get('${AppConstants.routineCurrCtx}/$_uid');

  Future<void> logSleepEvent(String screenOffTime, String screenOnTime, String date) async =>
      _post(AppConstants.routineSleepLog, {
        'user_id': _uid, 'screen_off_time': screenOffTime,
        'screen_on_time': screenOnTime, 'date': date,
      });

  Future<Map<String, dynamic>> getSleepSummary({int days = 7}) async =>
      _get('${AppConstants.routineSleepSumm}/$_uid?days=$days');

  Future<Map<String, dynamic>> generateRoutineInsights() async =>
      _post('${AppConstants.routineInsights}/$_uid', {});

  // ═══════════════════════════════════════════════════════════════════════
  //  TASKS & REMINDERS
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<dynamic>> getAllTasks({String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final r = await _get('${AppConstants.tasksBase}/$_uid$query');
    return r['tasks'] ?? [];
  }

  Future<void> confirmTask(String taskId) async =>
      _post('${AppConstants.tasksBase}/$_uid/confirm/$taskId', {});

  Future<void> updateTaskStatus(String taskId, String status) async =>
      _post('${AppConstants.tasksBase}/$_uid/update-status/$taskId?status=$status', {});

  Future<Map<String, dynamic>> getStressDensity() async =>
      _post(AppConstants.remindersStress, {'user_id': _uid});

  Future<Map<String, dynamic>> checkWellnessReminder(String type) async {
    final now = DateTime.now();
    return _post(AppConstants.remindersWellness, {
      'user_id': _uid, 'reminder_type': type,
      'current_time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    });
  }

  Future<void> dismissWellnessReminder(String type) async =>
      _post('${AppConstants.remindersDismiss}?user_id=$_uid&reminder_type=$type', {});

  Future<Map<String, dynamic>> getSmartReminders(String date) async =>
      _post(AppConstants.remindersSmartBtch, {'user_id': _uid, 'date': date});

  // ═══════════════════════════════════════════════════════════════════════
  //  CHAT & AI
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> sendChatMessage(String message, {String? sessionId}) async =>
      _post(AppConstants.chatMessage, {
        'user_id': _uid, 'message': message,
        if (sessionId != null) 'session_id': sessionId,
      });

  Future<Map<String, dynamic>> processVoiceNote(String transcribedText) async =>
      _post(AppConstants.chatVoice, {'user_id': _uid, 'transcribed_text': transcribedText});

  Future<List<dynamic>> getChatHistory() async {
    final r = await _get('${AppConstants.chatHistory}/$_uid');
    return r['history'] ?? [];
  }

  Future<void> clearChatHistory() async {
    await http.delete(
      Uri.parse('$_base${AppConstants.chatClear}/$_uid/clear'),
      headers: _headers,
    );
  }

  Future<Map<String, dynamic>> searchMessages(String query, {String? appFilter}) async =>
      _post(AppConstants.chatSearch, {
        'user_id': _uid, 'query': query,
        if (appFilter != null) 'app_filter': appFilter,
      });

  Future<Map<String, dynamic>> getStudyAvailability(String targetDate) async =>
      _post(AppConstants.chatStudyAvail, {'user_id': _uid, 'target_date': targetDate});

  // ═══════════════════════════════════════════════════════════════════════
  //  NOTES
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> processNoteText(String text, {String? subject}) async =>
      _post(AppConstants.notesProcess, {
        'user_id': _uid, 'text': text,
        if (subject != null) 'subject': subject,
      });

  Future<List<dynamic>> getNotesList({String? subject}) async {
    final query = subject != null ? '?subject=$subject' : '';
    final r = await _get('${AppConstants.notesList}/$_uid$query');
    return r['notes'] ?? [];
  }

  Future<Map<String, dynamic>> getNoteDetail(String noteId) async =>
      _get('${AppConstants.notesDelete}/$_uid/$noteId');

  Future<Map<String, dynamic>> askNotes(String question, {String? subject}) async =>
      _post(AppConstants.notesAsk, {
        'user_id': _uid, 'question': question,
        if (subject != null) 'subject_filter': subject,
      });

  Future<void> deleteNote(String noteId) async {
    await http.delete(
      Uri.parse('$_base${AppConstants.notesDelete}/$_uid/$noteId'),
      headers: _headers,
    );

    Future<List<dynamic>> semanticSearchNotes(String query, {int topK = 5}) async {
      final r = await _post(AppConstants.notesSemanticSearch, {
        'user_id': _uid, 'query': query, 'top_k': topK,
      });
      return r['results'] ?? [];
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  WELLNESS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> logPomodoroSession(Map<String, dynamic> session) async =>
      _post(AppConstants.wellnessPomodoro, {...session, 'user_id': _uid});

  Future<Map<String, dynamic>> getWeeklySummary() async =>
      _get('${AppConstants.wellnessSummary}/$_uid');

  Future<Map<String, dynamic>> getSleepReminder() async =>
      _get('${AppConstants.wellnessSleep}/$_uid');

  // ═══════════════════════════════════════════════════════════════════════
  //  EMAIL SUMMARIZATION
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> summarizeEmail(List<Map<String, dynamic>> emails) async =>
      _post(AppConstants.emailSummarize, {'user_id': _uid, 'emails': emails});

  Future<Map<String, dynamic>> summarizeFromNotifications({int hoursBack = 24}) async =>
      _post(AppConstants.emailFromNotifs, {'user_id': _uid, 'hours_back': hoursBack});

  Future<List<dynamic>> getEmailActionItems() async {
    final r = await _get('${AppConstants.emailActionItems}/$_uid');
    return r['action_items'] ?? [];
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LOCATION CONTEXT
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> saveOnboardingZones(List<Map<String, dynamic>> zones) async =>
      _post(AppConstants.locationOnboard, {'user_id': _uid, 'zones': zones});

  Future<Map<String, dynamic>> updateZoneTransition(String zoneName, String transition, {double? lat, double? lng}) async =>
      _post(AppConstants.locationTransition, {
        'user_id': _uid, 'zone_name': zoneName, 'transition': transition,
        if (lat != null) 'latitude': lat, if (lng != null) 'longitude': lng,
      });

  Future<Map<String, dynamic>> getCurrentZone() async =>
      _get('${AppConstants.locationCurrent}/$_uid');

  Future<Map<String, dynamic>> detectZoneFromGPS(double lat, double lng) async =>
      _post(AppConstants.locationDetect, {'user_id': _uid, 'latitude': lat, 'longitude': lng});

  Future<Map<String, dynamic>> getAdjustedReminderTime(String destZone, String eventTime) async =>
      _post(AppConstants.locationAdjusted, {
        'user_id': _uid, 'destination_zone': destZone, 'event_time': eventTime,
      });

  Future<Map<String, dynamic>> getSavedZones() async =>
      _get('${AppConstants.locationZones}/$_uid');

  Future<List<dynamic>> getLocationHistory({int limit = 50}) async {
    final r = await _get('${AppConstants.locationHistory}/$_uid?limit=$limit');
    return r['transitions'] ?? [];
  }
}