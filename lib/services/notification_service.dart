import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';
import 'user_prefs.dart';

/// Handles local notifications display and notification listener integration.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final _api = ApiService();

  /// Buffer incoming notifications before batching to backend
  final List<Map<String, dynamic>> _buffer = [];
  int _batchSize = 50;

  Future<void> initialize() async {
    _batchSize = await UserPrefs.getNotifBatchSize();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
  }

  /// Show a local notification (used for reminders, wellness nudges, etc.)
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'campusflow_channel', 'CampusFlow',
        channelDescription: 'CampusFlow notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// Show AI digest notification
  Future<void> showDigestNotification(Map<String, dynamic> digest) async {
    final greeting = digest['greeting'] ?? 'Good morning!';
    final urgentCount = (digest['urgent_items'] as List?)?.length ?? 0;
    await showNotification(
      id: 1000,
      title: '🌅 CampusFlow Morning Briefing',
      body: '$greeting${urgentCount > 0 ? ' • $urgentCount urgent items' : ''}',
      payload: 'digest',
    );
  }

  /// Show pre-class reminder
  Future<void> showPreClassReminder(Map<String, dynamic> classInfo) async {
    await showNotification(
      id: 2000 + (classInfo['subject']?.hashCode ?? 0).abs() % 1000,
      title: '📚 ${classInfo['subject']} in ${classInfo['minutes_until'] ?? 30} min',
      body: '${classInfo['room'] ?? ''} • ${classInfo['professor'] ?? ''}',
      payload: 'pre_class',
    );
  }

  /// Show wellness reminder
  Future<void> showWellnessReminder(String type, String message) async {
    final icons = {'water': '💧', 'stretch': '🧘', 'eye_rest': '👁', 'sleep': '😴'};
    await showNotification(
      id: 3000 + type.hashCode.abs() % 1000,
      title: '${icons[type] ?? '❤️'} Wellness Reminder',
      body: message,
      payload: 'wellness_$type',
    );
  }

  /// Queue a captured notification for batch upload
  void queueNotification(Map<String, dynamic> notification) {
    _buffer.add(notification);
    if (_buffer.length >= _batchSize) {
      flushBuffer();
    }
  }

  /// Send buffered notifications to backend
  Future<void> flushBuffer() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      await _api.ingestNotifications(batch);
    } catch (_) {
      // Re-add on failure
      _buffer.addAll(batch);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap — can navigate to specific screen based on payload
  }
}
