import 'api_service.dart';
import 'storage_service.dart';

/// Tracks screen on/off events and reports to backend for sleep detection.
class ScreenEventService {
  static final ScreenEventService _instance = ScreenEventService._internal();
  factory ScreenEventService() => _instance;
  ScreenEventService._internal();

  final _api = ApiService();
  final _storage = StorageService();
  DateTime? _lastScreenOff;

  /// Called when screen turns off
  Future<void> onScreenOff() async {
    _lastScreenOff = DateTime.now();
    final prefs = await _storage.prefs;
    await prefs.setString('last_screen_off', _lastScreenOff!.toIso8601String());
  }

  /// Called when screen turns on — checks if it was a sleep event
  Future<void> onScreenOn() async {
    final prefs = await _storage.prefs;
    final offStr = prefs.getString('last_screen_off');
    if (offStr == null) return;

    final offTime = DateTime.tryParse(offStr);
    if (offTime == null) return;

    final now = DateTime.now();
    final durationMinutes = now.difference(offTime).inMinutes;

    // If screen was off for 4+ hours, consider it sleep
    if (durationMinutes >= 240) {
      final offFormatted = '${offTime.hour.toString().padLeft(2, '0')}:${offTime.minute.toString().padLeft(2, '0')}';
      final onFormatted = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final date = '${offTime.year}-${offTime.month.toString().padLeft(2, '0')}-${offTime.day.toString().padLeft(2, '0')}';

      try {
        await _api.logSleepEvent(offFormatted, onFormatted, date);
      } catch (_) {}
    }
  }

  /// Get the last recorded screen off time
  Future<DateTime?> getLastScreenOff() async {
    final prefs = await _storage.prefs;
    final str = prefs.getString('last_screen_off');
    return str != null ? DateTime.tryParse(str) : null;
  }
}
