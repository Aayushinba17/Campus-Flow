import 'dart:async';
import 'api_service.dart';

/// Collects and batches app usage statistics to the backend.
class UsageStatsService {
  static final UsageStatsService _instance = UsageStatsService._internal();
  factory UsageStatsService() => _instance;
  UsageStatsService._internal();

  final _api = ApiService();
  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;

  /// Start periodic flushing (every 5 minutes)
  void startPeriodicFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(minutes: 5), (_) => flush());
  }

  /// Stop periodic flushing
  void stopPeriodicFlush() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Log an app usage event
  void logUsage({
    required String appName,
    required int durationSeconds,
    String? category,
  }) {
    _buffer.add({
      'app_name': appName,
      'duration_seconds': durationSeconds,
      'category': category ?? _categorize(appName),
      'timestamp': DateTime.now().toIso8601String(),
    });

    // Auto-flush if buffer gets large
    if (_buffer.length >= 50) flush();
  }

  /// Log a screen unlock event
  void logScreenUnlock() {
    _buffer.add({
      'event': 'screen_unlock',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Send buffered usage data to backend
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    try {
      await _api.sendUsageLogs(batch);
    } catch (_) {
      _buffer.addAll(batch); // Re-add on failure
    }
  }

  /// Auto-categorize common apps
  String _categorize(String appName) {
    final lower = appName.toLowerCase();
    if (['whatsapp', 'telegram', 'instagram', 'snapchat', 'twitter', 'facebook'].any((a) => lower.contains(a))) {
      return 'social_media';
    }
    if (['chrome', 'firefox', 'safari', 'browser'].any((a) => lower.contains(a))) {
      return 'browsing';
    }
    if (['youtube', 'netflix', 'prime', 'hotstar', 'spotify'].any((a) => lower.contains(a))) {
      return 'entertainment';
    }
    if (['notion', 'drive', 'docs', 'sheets', 'classroom', 'moodle'].any((a) => lower.contains(a))) {
      return 'productivity';
    }
    if (['pubg', 'bgmi', 'freefire', 'cod', 'game'].any((a) => lower.contains(a))) {
      return 'gaming';
    }
    return 'other';
  }

  /// Get today's usage statistics
  Future<Map<String, dynamic>> getDailyStats() async {
    // Return mock or calculated stats here since app_usage plugin was reverted
    return {
      'total_screen_minutes': 0,
      'study_minutes': 0,
    };
  }
}
