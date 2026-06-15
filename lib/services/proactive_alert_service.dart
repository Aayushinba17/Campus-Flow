import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../services/user_service.dart';
import '../services/user_prefs.dart';

class ProactiveAlertService {
  static final ProactiveAlertService _instance = ProactiveAlertService._internal();
  factory ProactiveAlertService() => _instance;
  ProactiveAlertService._internal();

  final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  final String _base = AppConstants.baseUrl;
  
  // Focus mode state
  String?  _activeFocusSessionId;
  bool     _focusModeActive = false;
  Timer?   _focusTimer;

  // Method channel for DND control
  static const _dndChannel = MethodChannel('campus_flow/activity_context');

  // ── Init ───────────────────────────────────────────────────────────────

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    await _createNotificationChannels();
    await _restoreFocusState();
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin = AndroidFlutterLocalNotificationsPlugin();

    // Deadline alerts — high importance
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'deadline_alerts', 'Deadline Alerts',
      description: 'Urgent deadline reminders',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));

    // Pre-class nudges — medium
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'pre_class', 'Class Reminders',
      description: 'Pre-class preparation nudges',
      importance: Importance.high,
    ));

    // Silence alerts — low
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'silence_alerts', 'Group Activity Alerts',
      description: 'Unusual chat silence detection',
      importance: Importance.defaultImportance,
    ));

    // Travel alerts — high
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'travel_alerts', 'Travel Reminders',
      description: 'Leave-now alerts for off-campus events',
      importance: Importance.max,
      playSound: true,
    ));

    // Focus mode — silent
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'focus_mode', 'Focus Mode',
      description: 'Focus session status',
      importance: Importance.low,
      playSound: false,
    ));
  }

  // ── 1. Check & fire all pending alerts ────────────────────────────────

  Future<void> checkAndFirePendingAlerts() async {
    try {
      final r = await http.get(
        Uri.parse('$_base/api/alerts/pending/${await UserService.getUserId()}'),
      ).timeout(const Duration(seconds: 10));

      if (r.statusCode != 200) return;
      final data = jsonDecode(r.body);
      final alerts = data['alerts'] as List? ?? [];

      for (final alert in alerts) {
        await _fireAlert(alert as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _fireAlert(Map<String, dynamic> alert) async {
    switch (alert['alert_type']) {
      case 'deadline_proximity':
        await _fireDeadlineAlert(alert);
        break;
      case 'pre_class_nudge':
        await _firePreClassNudge(alert);
        break;
      case 'travel_buffer':
        await _fireTravelAlert(alert);
        break;
    }
  }

  // ── 2. Deadline proximity alerts ──────────────────────────────────────

  Future<List<Map<String, dynamic>>> checkDeadlines({int hoursAhead = 24}) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/api/alerts/deadline-check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': (await UserService.getUserId()), 'hours_ahead': hoursAhead}),
      );
      final data = jsonDecode(r.body);
      final alerts = (data['alerts'] as List? ?? []).cast<Map<String, dynamic>>();

      for (final alert in alerts) {
        await _fireDeadlineAlert(alert);
      }
      return alerts;
    } catch (_) { return []; }
  }

  Future<void> _fireDeadlineAlert(Map<String, dynamic> alert) async {
    final urgency = alert['urgency'] as String? ?? 'medium';
    final importance = urgency == 'critical' ? Importance.max : Importance.high;

    await _notif.show(
      alert['alert_id'].hashCode,
      alert['title'] as String? ?? 'Deadline approaching',
      alert['body']  as String? ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'deadline_alerts', 'Deadline Alerts',
          importance: importance,
          priority: urgency == 'critical' ? Priority.max : Priority.high,
          styleInformation: BigTextStyleInformation(
            alert['body'] as String? ?? '',
            summaryText: alert['related_note_title'] != null
              ? '📎 Related notes: ${alert['related_note_title']}'
              : 'Tap to view task',
          ),
          actions: [
            const AndroidNotificationAction('mark_done', '✅ Mark Done'),
            const AndroidNotificationAction('view_notes', '📖 View Notes'),
          ],
        ),
      ),
      payload: jsonEncode({
        'type': 'deadline',
        'task_id': alert['task_id'],
        'note_id': alert['related_note_id'],
      }),
    );
  }

  // ── 3. Unusual silence check ──────────────────────────────────────────

  Future<Map<String, dynamic>?> checkSilence(String appName, {int silenceHours = 6}) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/api/alerts/silence-check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': (await UserService.getUserId()),
          'app_name': appName,
          'silence_hours': silenceHours,
        }),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['is_silent'] == true) {
        await _fireSilenceAlert(data);
        return data;
      }
      return null;
    } catch (_) { return null; }
  }

  Future<void> _fireSilenceAlert(Map<String, dynamic> alert) async {
    await _notif.show(
      alert['alert_id'].hashCode,
      alert['title'] as String? ?? 'Unusual silence detected',
      alert['message'] as String? ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'silence_alerts', 'Group Activity Alerts',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: jsonEncode({'type': 'silence', 'app': alert['app_name']}),
    );
  }

  // ── 4. Pre-class nudge ────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getPreClassNudge({
    required String subject,
    required String startTime,
    String? room,
    String? professor,
  }) async {
    final prefsMins = await UserPrefs.getPreClassReminderMins();
    try {
      final r = await http.post(
        Uri.parse('$_base/api/alerts/pre-class-nudge'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id':   (await UserService.getUserId()),
          'subject':   subject,
          'start_time': startTime,
          'reminder_mins': prefsMins,
          if (room != null)      'room': room,
          if (professor != null) 'professor': professor,
        }),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      await _firePreClassNudge(data);
      return data;
    } catch (_) { return null; }
  }

  Future<void> _firePreClassNudge(Map<String, dynamic> alert) async {
    await _notif.show(
      (alert['alert_id'] ?? 'preclass').hashCode,
      alert['title'] as String? ?? 'Class starting soon',
      alert['body']  as String? ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'pre_class', 'Class Reminders',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''),
        ),
      ),
      payload: jsonEncode({'type': 'pre_class', 'subject': alert['subject']}),
    );
  }

  // ── 5. Travel buffer alert ────────────────────────────────────────────

  Future<Map<String, dynamic>?> checkTravelBuffer({
    required String eventTitle,
    required String eventTime,
    bool isOffCampus = false,
    int travelMinutes = 30,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/api/alerts/travel-buffer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id':        (await UserService.getUserId()),
          'event_title':    eventTitle,
          'event_time':     eventTime,
          'is_off_campus':  isOffCampus,
          'travel_minutes': travelMinutes,
        }),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['should_alert'] == true) {
        await _fireTravelAlert(data);
        return data;
      }
      return null;
    } catch (_) { return null; }
  }

  Future<void> _fireTravelAlert(Map<String, dynamic> alert) async {
    await _notif.show(
      (alert['alert_id'] ?? 'travel').hashCode,
      alert['title'] as String? ?? 'Time to leave!',
      alert['body']  as String? ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'travel_alerts', 'Travel Reminders',
          importance: Importance.max,
          priority: Priority.max,
          color: Color(0xFFE8592B),
          actions: [
            AndroidNotificationAction('already_left', '✅ Already left'),
            AndroidNotificationAction('snooze_5', '⏰ Snooze 5 min'),
          ],
        ),
      ),
      payload: jsonEncode({'type': 'travel', 'event': alert['event_title']}),
    );
  }

  // ── 6. Focus mode ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> startFocusMode({
    required String sessionType,
    required int durationMinutes,
    String? subject,
  }) async {
    try {
      final r = await http.post(
        Uri.parse('$_base/api/alerts/focus-mode/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id':          (await UserService.getUserId()),
          'session_type':     sessionType,
          'duration_minutes': durationMinutes,
          if (subject != null) 'subject': subject,
        }),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;

      _activeFocusSessionId = data['session_id'] as String?;
      _focusModeActive = true;

      // Enable Android DND via method channel
      await _enableDND(true);

      // Show persistent focus notification
      await _showFocusNotification(data, durationMinutes);

      // Auto-end timer
      _focusTimer?.cancel();
      _focusTimer = Timer(Duration(minutes: durationMinutes), () => endFocusMode());

      return data;
    } catch (_) { return null; }
  }

  Future<Map<String, dynamic>?> endFocusMode() async {
    if (_activeFocusSessionId == null) return null;
    _focusTimer?.cancel();

    try {
      final r = await http.post(
        Uri.parse('$_base/api/alerts/focus-mode/end'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id':    (await UserService.getUserId()),
          'session_id': _activeFocusSessionId,
        }),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;

      _focusModeActive = false;
      _activeFocusSessionId = null;

      // Disable DND
      await _enableDND(false);

      // Cancel focus notification, show completion
      await _notif.cancel(999);
      await _notif.show(
        998,
        data['title'] as String? ?? 'Focus session complete!',
        data['message'] as String? ?? 'Great work!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'focus_mode', 'Focus Mode',
            importance: Importance.defaultImportance,
          ),
        ),
      );
      return data;
    } catch (_) { return null; }
  }

  Future<void> _showFocusNotification(Map<String, dynamic> data, int minutes) async {
    await _notif.show(
      999,   // Fixed ID so we can update/cancel it
      data['title'] as String? ?? '🎯 Focus Mode Active',
      '${data['message']} ($minutes min)',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'focus_mode', 'Focus Mode',
          importance: Importance.low,
          ongoing: true,      // Can't be swiped away
          autoCancel: false,
          showProgress: true,
          maxProgress: minutes,
          progress: 0,
          actions: const [
            AndroidNotificationAction('end_focus', '⏹ End Session'),
          ],
        ),
      ),
    );
  }

  Future<void> _enableDND(bool enable) async {
    try {
      await _dndChannel.invokeMethod(
        enable ? 'enableDND' : 'disableDND',
      );
    } catch (_) {
      // DND requires special permission — fail silently if not granted
    }
  }

  Future<void> _restoreFocusState() async {
    try {
      final r = await http.get(
        Uri.parse('$_base/api/alerts/focus-mode/active/${await UserService.getUserId()}'),
      );
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['has_active_session'] == true) {
        final session = data['session'] as Map<String, dynamic>;
        _activeFocusSessionId = session['session_id'] as String?;
        _focusModeActive = true;
        final minsRemaining = data['minutes_remaining'] as int? ?? 0;
        if (minsRemaining > 0) {
          _focusTimer = Timer(Duration(minutes: minsRemaining), () => endFocusMode());
        }
      }
    } catch (_) {}
  }

  // ── Notification tap handler ───────────────────────────────────────────

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String?;
      // Navigation handled by app's notification router
      _notificationTapController.add({'type': type, 'data': data});
    } catch (_) {}
  }

  // Stream for the app to listen to notification taps
  final _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onNotificationTap =>
      _notificationTapController.stream;

  // ── Getters ────────────────────────────────────────────────────────────

  bool get isFocusModeActive => _focusModeActive;
  String? get activeFocusSessionId => _activeFocusSessionId;
}