import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../utils/constants.dart';
import '../services/user_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String _base = AppConstants.baseUrl;
  //final String await _uid  = AppConstants.userId;
  Future<String> get _uid async => await UserService.getUserId();

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ── Generic helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await http.get(Uri.parse('$_base$path'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('API Error (${r.statusCode}): ${r.body}');
    }
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      Uri.parse('$_base$path'), headers: _headers, body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('API Error (${r.statusCode}): ${r.body}');
    }
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
    final uri = Uri.parse('$_base${AppConstants.scheduleUpload}?user_id=${await _uid}');
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
      _get('${AppConstants.scheduleToday}/${await _uid}');

  Future<Map<String, dynamic>> getSchedule() async =>
      _get('${AppConstants.scheduleClasses}/${await _uid}');

  Future<Map<String, dynamic>> addManualEvent(Map<String, dynamic> event) async =>
      _post(AppConstants.scheduleEvent, {...event, 'user_id': await _uid});

  Future<Map<String, dynamic>> getFreeSlotSuggestions(String date) async =>
      _post(AppConstants.scheduleFreeSlots, {'user_id': await _uid, 'date': date});

  Future<Map<String, dynamic>> detectBookings({int hoursBack = 48}) async =>
      _post(AppConstants.scheduleBookings, {'user_id': await _uid, 'hours_back': hoursBack});

  Future<Map<String, dynamic>> confirmBooking(String itemId) async =>
      _post('${AppConstants.scheduleConfirmBk}/${await _uid}/$itemId', {});

  Future<Map<String, dynamic>> dismissBooking(String itemId) async {
    final r = await http.delete(
      Uri.parse('$_base${AppConstants.scheduleDismissBk}/${await _uid}/$itemId'),
      headers: _headers,
    );
    return jsonDecode(r.body);
  }

  Future<Map<String, dynamic>> getExamCountdown(String examSubject, String examDate, {String? examTime}) async =>
      _post(AppConstants.scheduleExamCount, {
        'user_id': await _uid, 'exam_subject': examSubject, 'exam_date': examDate,
        if (examTime != null) 'exam_time': examTime,
      });

  Future<Map<String, dynamic>> getExamChecklist(String examSubject, String examDate) async =>
      _post(AppConstants.scheduleChecklist, {
        'user_id': await _uid, 'exam_subject': examSubject, 'exam_date': examDate,
      });

  // ═══════════════════════════════════════════════════════════════════════
  //  NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> ingestNotifications(List<Map<String, dynamic>> notifications) async =>
      _post(AppConstants.notifIngest, {'user_id': await _uid, 'notifications': notifications});

  Future<Map<String, dynamic>> getMorningDigest({int hoursBack = 8}) async =>
      _post(AppConstants.notifDigest, {'user_id': await _uid, 'hours_back': hoursBack});

  Future<List<dynamic>> getRecentNotifications({int hours = 24, int minPriority = 1}) async {
    final r = await _get('${AppConstants.notifRecent}/${await _uid}?hours=$hours&min_priority=$minPriority');
    return r['notifications'] ?? [];
  }

  Future<List<dynamic>> getExtractedDeadlines({int daysAhead = 7}) async {
    final r = await _get('${AppConstants.notifDeadlines}/${await _uid}?days_ahead=$daysAhead');
    return r['deadlines'] ?? [];
  }

  Future<Map<String, dynamic>> getMissedCallContext({
    required String callerName, required String missedAt,
    List<Map<String, dynamic>> followUpMessages = const [],
  }) async =>
      _post(AppConstants.notifMissedCall, {
        'user_id': await _uid, 'caller_name': callerName, 'missed_at': missedAt,
        'follow_up_messages': followUpMessages,
      });

  Future<List<dynamic>> getMissedCalls() async {
    final r = await _get('${AppConstants.notifMissedCalls}/${await _uid}');
    return r['missed_calls'] ?? [];
  }

  Future<Map<String, dynamic>> extractDeadlines({List<String>? notificationIds, int hoursBack = 24}) async =>
      _post(AppConstants.notifExtractDead, {
        'user_id': await _uid, 
        if (notificationIds != null) 'notification_ids': notificationIds,
        'hours_back': hoursBack
      });

  Future<Map<String, dynamic>> getNotificationStats() async =>
      _get('${AppConstants.notifStats}/${await _uid}');

  // ═══════════════════════════════════════════════════════════════════════
  //  ROUTINE
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> sendUsageLogs(List<Map<String, dynamic>> entries) async =>
      _post(AppConstants.routineUsageLog, {'user_id': await _uid, 'entries': entries});

  Future<Map<String, dynamic>> getUsageHeatmap({int days = 7}) async =>
      _get('${AppConstants.routineHeatmap}/${await _uid}?days=$days');

  Future<void> updateActivityContext(Map<String, dynamic> context) async =>
      _post(AppConstants.routineContext, {...context, 'user_id': await _uid});

  Future<Map<String, dynamic>> getCurrentContext() async =>
      _get('${AppConstants.routineCurrCtx}/${await _uid}');

  Future<void> logSleepEvent(String screenOffTime, String screenOnTime, String date) async =>
      _post(AppConstants.routineSleepLog, {
        'user_id': await _uid, 'screen_off_time': screenOffTime,
        'screen_on_time': screenOnTime, 'date': date,
      });

  Future<Map<String, dynamic>> getSleepSummary({int days = 7}) async =>
      _get('${AppConstants.routineSleepSumm}/${await _uid}?days=$days');

  Future<Map<String, dynamic>> generateRoutineInsights() async =>
      _post('${AppConstants.routineInsights}/${await _uid}', {});

  // ═══════════════════════════════════════════════════════════════════════
  //  TASKS & REMINDERS
  // ═══════════════════════════════════════════════════════════════════════

  Future<List<dynamic>> getAllTasks({String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final r = await _get('${AppConstants.tasksBase}/${await _uid}$query');
    return r['tasks'] ?? [];
  }

  Future<void> confirmTask(String taskId) async =>
      _post('${AppConstants.tasksBase}/${await _uid}/confirm/$taskId', {});

  Future<void> updateTaskStatus(String taskId, String status) async =>
      _post('${AppConstants.tasksBase}/${await _uid}/update-status/$taskId?status=$status', {});

  Future<Map<String, dynamic>> getStressDensity() async =>
      _post(AppConstants.remindersStress, {'user_id': await _uid});

  Future<Map<String, dynamic>> checkWellnessReminder(String type) async {
    final now = DateTime.now();
    return _post(AppConstants.remindersWellness, {
      'user_id': await _uid, 'reminder_type': type,
      'current_time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    });
  }

  Future<void> dismissWellnessReminder(String type) async =>
      _post('${AppConstants.remindersDismiss}?user_id=${await _uid}&reminder_type=$type', {});

  Future<Map<String, dynamic>> getSmartReminders(String currentTime) async =>
      _post(AppConstants.remindersSmartBtch, {'user_id': await _uid, 'current_time': currentTime});

  // ═══════════════════════════════════════════════════════════════════════
  //  CHAT & AI
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> sendChatMessage(String message, {String? sessionId}) async {
  final uid = await _uid;
  return _post(AppConstants.chatMessage, {
    'user_id': uid,
    'message': message,
    if (sessionId != null) 'session_id': sessionId,
  });
}

  Future<Map<String, dynamic>> processVoiceNote(String transcribedText) async =>
      _post(AppConstants.chatVoice, {'user_id': await _uid, 'transcribed_text': transcribedText});

  Future<List<dynamic>> getChatHistory() async {
    final r = await _get('${AppConstants.chatHistory}/${await _uid}');
    return r['history'] ?? [];
  }

  Future<void> clearChatHistory() async {
    await http.delete(
      Uri.parse('$_base${AppConstants.chatClear}/${await _uid}/clear'),
      headers: _headers,
    );
  }

  Future<Map<String, dynamic>> searchMessages(String query, {String? appFilter}) async =>
      _post(AppConstants.chatSearch, {
        'user_id': await _uid, 'query': query,
        if (appFilter != null) 'app_filter': appFilter,
      });

  Future<Map<String, dynamic>> getStudyAvailability(String targetDate) async =>
      _post(AppConstants.chatStudyAvail, {'user_id': await _uid, 'target_date': targetDate});

  // ═══════════════════════════════════════════════════════════════════════
  //  NOTES
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> processNoteText(String text, {String? subject}) async =>
      _post(AppConstants.notesProcess, {
        'user_id': await _uid, 'text': text,
        if (subject != null) 'subject': subject,
      });

  Future<List<dynamic>> getNotesList({String? subject}) async {
    final query = subject != null ? '?subject=$subject' : '';
    final r = await _get('${AppConstants.notesList}/${await _uid}$query');
    return r['notes'] ?? [];
  }

  Future<Map<String, dynamic>> getNoteDetail(String noteId) async =>
      _get('${AppConstants.notesDelete}/${await _uid}/$noteId');

  Future<Map<String, dynamic>> askNotes(String question, {String? subject}) async =>
      _post(AppConstants.notesAsk, {
        'user_id': await _uid, 'question': question,
        if (subject != null) 'subject_filter': subject,
      });

  Future<void> deleteNote(String noteId) async {
    await http.delete(
      Uri.parse('$_base${AppConstants.notesDelete}/${await _uid}/$noteId'),
      headers: _headers,
    );
  }

  Future<String> getClassroomAuthUrl() async {
    final r = await _get('${AppConstants.classroomOAuthStart}?user_id=${await _uid}');
    return r['auth_url'] as String;
  } 

  Future<bool> isClassroomConnected() async {
    final r = await _get('${AppConstants.classroomStatus}/${await _uid}');
    return r['connected'] == true;
  }

  Future<Map<String, dynamic>> syncClassroom() async =>
    _post(AppConstants.classroomSync, {'user_id': await _uid});

  Future<Map<String, dynamic>> syncClassroomAnnouncements() async =>
    _post(AppConstants.classroomSyncAnn, {'user_id': await _uid});
  
  Future<List<dynamic>> semanticSearchNotes(String query, {int topK = 5}) async {
  final uid = await _uid;
  final r = await _post(AppConstants.notesSemanticSearch, {
    'user_id': uid, 'query': query, 'top_k': topK,
  });
  return r['results'] ?? [];
}

  Future<Map<String, dynamic>> reembedNotes() async =>
      _post('${AppConstants.notesReembed}/${await _uid}', {});

  // ═══════════════════════════════════════════════════════════════════════
  //  WELLNESS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> logPomodoroSession(Map<String, dynamic> session) async =>
      _post(AppConstants.wellnessPomodoro, {...session, 'user_id': await _uid});

  Future<Map<String, dynamic>> getWeeklySummary() async =>
      _get('${AppConstants.wellnessSummary}/${await _uid}');

  Future<Map<String, dynamic>> getSleepReminder() async =>
      _get('${AppConstants.wellnessSleep}/${await _uid}');

  // ═══════════════════════════════════════════════════════════════════════
  //  EMAIL SUMMARIZATION
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> summarizeEmail(List<Map<String, dynamic>> messages) async =>
      _post(AppConstants.emailSummarize, {'user_id': await _uid, 'messages': messages});

  Future<Map<String, dynamic>> summarizeFromNotifications({int hoursBack = 24}) async =>
      _post(AppConstants.emailFromNotifs, {'user_id': await _uid, 'hours_back': hoursBack});

  Future<List<dynamic>> getEmailActionItems() async {
    final r = await _get('${AppConstants.emailActionItems}/${await _uid}');
    return r['action_items'] ?? [];
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  LOCATION CONTEXT
  // ═══════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> saveOnboardingZones(List<Map<String, dynamic>> zones) async =>
      _post(AppConstants.locationOnboard, {'user_id': await _uid, 'zones': zones});

  Future<Map<String, dynamic>> updateZoneTransition(String zoneName, String transition, {double? lat, double? lng}) async =>
      _post(AppConstants.locationTransition, {
        'user_id': await _uid, 'zone_name': zoneName, 'transition': transition,
        if (lat != null) 'latitude': lat, if (lng != null) 'longitude': lng,
      });

  Future<Map<String, dynamic>> getCurrentZone() async =>
      _get('${AppConstants.locationCurrent}/${await _uid}');

  Future<Map<String, dynamic>> detectZoneFromGPS(double lat, double lng) async =>
      _post(AppConstants.locationDetect, {'user_id': await _uid, 'latitude': lat, 'longitude': lng});

  Future<Map<String, dynamic>> getAdjustedReminderTime(String destZone, String eventTime) async =>
      _post(AppConstants.locationAdjusted, {
        'user_id': await _uid, 'destination_zone': destZone, 'event_time': eventTime,
      });

  Future<Map<String, dynamic>> getSavedZones() async =>
      _get('${AppConstants.locationZones}/${await _uid}');

  Future<List<dynamic>> getLocationHistory({int limit = 50}) async {
    final r = await _get('${AppConstants.locationHistory}/${await _uid}?limit=$limit');
    return r['transitions'] ?? [];
  }
  Future<Map<String, dynamic>> processNoteFile(File file, {String? subject}) async {
  final uid = await _uid;
  final uri = Uri.parse('$_base${AppConstants.notesProcessFile}?user_id=$uid'
      '${subject != null ? '&subject=$subject' : ''}');
  final req = http.MultipartRequest('POST', uri);
  req.files.add(await http.MultipartFile.fromPath('file', file.path));
  final streamed = await req.send().timeout(const Duration(seconds: 90));
  final r = await http.Response.fromStream(streamed);
  if (r.statusCode != 200) throw Exception('File upload failed: ${r.body}');
  return jsonDecode(r.body);
}

  Future<Map<String, dynamic>> disconnectClassroom() async {
  final uid = await _uid;
  final r = await http.delete(
    Uri.parse('$_base${AppConstants.classroomDisconnect}/$uid'),
    headers: _headers,
  );
  return jsonDecode(r.body);
}
}