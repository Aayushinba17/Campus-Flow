import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Manages wellness reminder scheduling and tracking.
class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  final _api = ApiService();

  /// Check if a wellness reminder should fire based on time elapsed
  Future<Map<String, dynamic>?> checkReminder(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final lastKey = 'last_${type}_reminder';
    final lastTime = prefs.getString(lastKey);

    // Default intervals in minutes
    final intervals = {
      'water': 90,
      'stretch': 60,
      'eye_rest': 30,
    };

    if (lastTime != null) {
      final last = DateTime.tryParse(lastTime);
      if (last != null) {
        final elapsed = DateTime.now().difference(last).inMinutes;
        if (elapsed < (intervals[type] ?? 60)) return null;
      }
    }

    try {
      final result = await _api.checkWellnessReminder(type);
      if (result['should_remind'] == true) {
        await prefs.setString(lastKey, DateTime.now().toIso8601String());
        return result;
      }
    } catch (_) {}
    return null;
  }

  /// Dismiss a wellness reminder
  Future<void> dismissReminder(String type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_${type}_reminder', DateTime.now().toIso8601String());
    try { await _api.dismissWellnessReminder(type); } catch (_) {}
  }

  /// Check all wellness reminders
  Future<List<Map<String, dynamic>>> checkAllReminders() async {
    final results = <Map<String, dynamic>>[];
    for (final type in ['water', 'stretch', 'eye_rest']) {
      final r = await checkReminder(type);
      if (r != null) results.add({...r, 'type': type});
    }
    return results;
  }
}
