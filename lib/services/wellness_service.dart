// lib/services/wellness_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/wellness_model.dart';
import '../utils/constants.dart';

class WellnessService {
  static const String baseUrl = '${AppConstants.baseUrl}/api/wellness';

  // ─── Local state keys ───
  static const String _cupsKey = 'cups_today';
  static const String _cupsDateKey = 'cups_date';
  static const String _lastHydrationKey = 'last_hydration_reminder';
  static const String _dismissedKey = 'dismissed_reminders';
  static const String _screenOffTimesKey = 'screen_off_times';

  // ─────────────────────────────────────────────
  // LOCAL PERSISTENCE
  // ─────────────────────────────────────────────

  static Future<int> getCupsToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final savedDate = prefs.getString(_cupsDateKey) ?? '';
    if (savedDate != today) {
      await prefs.setInt(_cupsKey, 0);
      await prefs.setString(_cupsDateKey, today);
      return 0;
    }
    return prefs.getInt(_cupsKey) ?? 0;
  }

  static Future<void> addCup() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await prefs.setString(_cupsDateKey, today);
    final current = prefs.getInt(_cupsKey) ?? 0;
    await prefs.setInt(_cupsKey, current + 1);
  }

  static Future<int> minutesSinceLastHydrationReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_lastHydrationKey);
    if (lastMs == null) return 999;
    final diff = DateTime.now().millisecondsSinceEpoch - lastMs;
    return diff ~/ 60000;
  }

  static Future<void> markHydrationReminderSent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastHydrationKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<List<String>> getDismissedReminders() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_dismissedKey) ?? [];
  }

  static Future<void> dismissReminder(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_dismissedKey) ?? [];
    if (!list.contains(key)) list.add(key);
    await prefs.setStringList(_dismissedKey, list);
  }

  static Future<void> clearDismissedReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissedKey);
  }

  static Future<void> saveScreenOffTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_screenOffTimesKey) ?? [];
    list.add(time);
    // Keep only last 7
    if (list.length > 7) list.removeAt(0);
    await prefs.setStringList(_screenOffTimesKey, list);
  }

  static Future<List<String>> getWeeklyScreenOffTimes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_screenOffTimesKey) ?? [];
  }

  // ─────────────────────────────────────────────
  // API CALLS
  // ─────────────────────────────────────────────

  static Future<HydrationResponse> checkHydration(WellnessContext ctx) async {
    final cups = await getCupsToday();
    final minsSince = await minutesSinceLastHydrationReminder();
    final dismissed = await getDismissedReminders();

    final contextWithDismissed = WellnessContext(
      schedule: ctx.schedule,
      screenOnMinutesToday: ctx.screenOnMinutesToday,
      currentTime: ctx.currentTime,
      dateLabel: ctx.dateLabel,
      deadlinesIn48h: ctx.deadlinesIn48h,
      unreadUrgentMessages: ctx.unreadUrgentMessages,
      dismissedReminders: dismissed,
      mealTimes: ctx.mealTimes,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/hydration/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'context': contextWithDismissed.toJson(),
          'minutes_since_last_reminder': minsSince,
          'cups_today': cups,
        }),
      );
      return HydrationResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      return HydrationResponse(shouldRemind: false, reason: 'error');
    }
  }

  static Future<SleepResponse> checkSleep({
    required WellnessContext ctx,
    String? tomorrowFirstClass,
    bool screenActiveLast30min = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sleep/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'context': ctx.toJson(),
          'tomorrow_first_class_time': tomorrowFirstClass,
          'screen_active_last_30min': screenActiveLast30min,
        }),
      );
      return SleepResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      return SleepResponse(shouldRemind: false, reason: 'error');
    }
  }

  static Future<MealResponse> checkMeal({
    required WellnessContext ctx,
    required String mealType,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/meal/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'context': ctx.toJson(),
          'meal_type': mealType,
        }),
      );
      return MealResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      return MealResponse(shouldRemind: false, reason: 'error');
    }
  }

  static Future<StressResponse> calculateStress(WellnessContext ctx) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/stress/calculate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'context': ctx.toJson()}),
      );
      return StressResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      return StressResponse(show: false, level: 'low');
    }
  }

  static Future<WeeklySummaryResponse> getWeeklySummary({
    required WellnessContext ctx,
    int studyMinutes = 0,
    int leisureMinutes = 0,
    int totalScreenMinutes = 0,
  }) async {
    final screenOffTimes = await getWeeklyScreenOffTimes();
    final ctxWithHistory = WellnessContext(
      schedule: ctx.schedule,
      screenOnMinutesToday: ctx.screenOnMinutesToday,
      currentTime: ctx.currentTime,
      dateLabel: ctx.dateLabel,
      deadlinesIn48h: ctx.deadlinesIn48h,
      unreadUrgentMessages: ctx.unreadUrgentMessages,
      dismissedReminders: ctx.dismissedReminders,
      weeklyScreenOffTimes: screenOffTimes,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/weekly-summary'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'context': ctxWithHistory.toJson(),
          'study_minutes': studyMinutes,
          'leisure_minutes': leisureMinutes,
          'total_screen_minutes': totalScreenMinutes,
        }),
      );
      return WeeklySummaryResponse.fromJson(jsonDecode(response.body));
    } catch (e) {
      return WeeklySummaryResponse(
        aiSummary: 'Great job this week! Rest up for the next one.',
      );
    }
  }
}