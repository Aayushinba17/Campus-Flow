import 'package:shared_preferences/shared_preferences.dart';

/// Persistent local storage for user data & settings.
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── User Info ──────────────────────────────────────────────────────────

  Future<String> getUserName() async => (await prefs).getString('user_name') ?? 'Student';
  Future<void> setUserName(String name) async => (await prefs).setString('user_name', name);

  Future<bool> isOnboarded() async => (await prefs).getBool('onboarding_complete') ?? false;
  Future<void> setOnboarded(bool value) async => (await prefs).setBool('onboarding_complete', value);

  // ── Chat ───────────────────────────────────────────────────────────────

  Future<String?> getChatSessionId() async => (await prefs).getString('chat_session_id');
  Future<void> setChatSessionId(String id) async => (await prefs).setString('chat_session_id', id);

  // ── Wellness ──────────────────────────────────────────────────────────

  Future<int> getPomodoroCount() async => (await prefs).getInt('pomodoro_count') ?? 0;
  Future<void> incrementPomodoroCount() async {
    final count = await getPomodoroCount();
    (await prefs).setInt('pomodoro_count', count + 1);
  }

  Future<DateTime?> getLastWellnessReminder(String type) async {
    final str = (await prefs).getString('last_${type}_reminder');
    return str != null ? DateTime.tryParse(str) : null;
  }

  Future<void> setLastWellnessReminder(String type) async {
    (await prefs).setString('last_${type}_reminder', DateTime.now().toIso8601String());
  }

  // ── Location ──────────────────────────────────────────────────────────

  Future<String?> getCurrentZone() async => (await prefs).getString('current_zone');
  Future<void> setCurrentZone(String zone) async => (await prefs).setString('current_zone', zone);

  // ── Settings ──────────────────────────────────────────────────────────

  Future<bool> isDarkMode() async => (await prefs).getBool('dark_mode') ?? false;
  Future<void> setDarkMode(bool value) async => (await prefs).setBool('dark_mode', value);

  Future<bool> areNotificationsEnabled() async => (await prefs).getBool('notif_enabled') ?? true;
  Future<void> setNotificationsEnabled(bool value) async => (await prefs).setBool('notif_enabled', value);

  /// Clear all stored data
  Future<void> clearAll() async => (await prefs).clear();
}
