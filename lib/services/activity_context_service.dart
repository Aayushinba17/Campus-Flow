import 'api_service.dart';

/// Tracks and reports the user's current activity context
/// (studying, browsing, gaming, etc.) to the backend.
class ActivityContextService {
  static final ActivityContextService _instance = ActivityContextService._internal();
  factory ActivityContextService() => _instance;
  ActivityContextService._internal();

  final _api = ApiService();
  String _currentActivity = 'idle';
  DateTime _activityStart = DateTime.now();

  String get currentActivity => _currentActivity;

  /// Update the current activity context
  Future<void> updateActivity(String activity) async {
    if (activity == _currentActivity) return;

    // Log the previous activity duration
    final duration = DateTime.now().difference(_activityStart).inMinutes;
    if (duration > 0 && _currentActivity != 'idle') {
      try {
        await _api.updateActivityContext({
          'activity': _currentActivity,
          'duration_minutes': duration,
          'ended_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    }

    _currentActivity = activity;
    _activityStart = DateTime.now();
  }

  /// Report current context to backend (called periodically)
  Future<void> reportCurrentContext() async {
    try {
      await _api.updateActivityContext({
        'activity': _currentActivity,
        'since': _activityStart.toIso8601String(),
        'duration_minutes': DateTime.now().difference(_activityStart).inMinutes,
      });
    } catch (_) {}
  }

  /// Get current context from backend
  Future<Map<String, dynamic>> fetchContext() async {
    try {
      return await _api.getCurrentContext();
    } catch (_) {
      return {'current_activity': _currentActivity, 'since': _activityStart.toIso8601String()};
    }
  }
}
