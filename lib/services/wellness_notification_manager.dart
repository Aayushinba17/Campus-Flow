// lib/services/wellness_notification_manager.dart
//
// Call WellnessNotificationManager.runChecks(ctx) periodically.
// Best triggered from a background timer or when app resumes.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/wellness_model.dart';
import 'wellness_service.dart';

class WellnessNotificationManager {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  // ─────────────────────────────────────────────
  // INIT — call once in main.dart
  // ─────────────────────────────────────────────

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels
    const hydrationChannel = AndroidNotificationChannel(
      'wellness_hydration',
      'Hydration Reminders',
      description: 'Water intake reminders',
      importance: Importance.defaultImportance,
    );
    const sleepChannel = AndroidNotificationChannel(
      'wellness_sleep',
      'Sleep Reminders',
      description: 'Sleep nudges based on your schedule',
      importance: Importance.high,
    );
    const mealChannel = AndroidNotificationChannel(
      'wellness_meal',
      'Meal Reminders',
      description: 'Meal timing nudges',
      importance: Importance.defaultImportance,
    );
    const stressChannel = AndroidNotificationChannel(
      'wellness_stress',
      'Stress Alerts',
      description: 'Busy period notifications',
      importance: Importance.low,
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(hydrationChannel);
    await androidPlugin?.createNotificationChannel(sleepChannel);
    await androidPlugin?.createNotificationChannel(mealChannel);
    await androidPlugin?.createNotificationChannel(stressChannel);

    _initialized = true;
  }

  static void _onNotificationTap(NotificationResponse details) {
    // Handle tap — navigate to wellness screen
    // Use a global navigator key in production
  }

  // ─────────────────────────────────────────────
  // RUN ALL CHECKS — call this periodically
  // ─────────────────────────────────────────────

  static Future<void> runChecks({
    required WellnessContext ctx,
    String? tomorrowFirstClass,
    bool screenActive = true,
  }) async {
    await init();
    await _checkHydration(ctx);
    await _checkMeals(ctx);
    await _checkSleep(
      ctx: ctx,
      tomorrowFirstClass: tomorrowFirstClass,
      screenActive: screenActive,
    );
    await _checkStress(ctx);
  }

  // ─────────────────────────────────────────────
  // HYDRATION CHECK
  // ─────────────────────────────────────────────

  static Future<void> _checkHydration(WellnessContext ctx) async {
    final result = await WellnessService.checkHydration(ctx);
    if (result.shouldRemind) {
      await _showNotification(
        id: 1001,
        channelId: 'wellness_hydration',
        title: result.title ?? '💧 Hydration Check',
        body: result.body ?? 'Time to drink some water!',
      );
      await WellnessService.markHydrationReminderSent();
    }
  }

  // ─────────────────────────────────────────────
  // MEAL CHECKS
  // ─────────────────────────────────────────────

  static Future<void> _checkMeals(WellnessContext ctx) async {
    const meals = ['breakfast', 'lunch', 'dinner'];
    const ids = [2001, 2002, 2003];

    for (int i = 0; i < meals.length; i++) {
      final result = await WellnessService.checkMeal(
        ctx: ctx,
        mealType: meals[i],
      );
      if (result.shouldRemind) {
        await _showNotification(
          id: ids[i],
          channelId: 'wellness_meal',
          title: result.title ?? '🍴 Meal Time',
          body: result.body ?? 'Time to eat!',
        );
      }
    }
  }

  // ─────────────────────────────────────────────
  // SLEEP CHECK
  // ─────────────────────────────────────────────

  static Future<void> _checkSleep({
    required WellnessContext ctx,
    String? tomorrowFirstClass,
    bool screenActive = true,
  }) async {
    final result = await WellnessService.checkSleep(
      ctx: ctx,
      tomorrowFirstClass: tomorrowFirstClass,
      screenActiveLast30min: screenActive,
    );

    if (result.shouldRemind) {
      await _showNotification(
        id: 3001,
        channelId: 'wellness_sleep',
        title: result.title ?? '🌙 Sleep Reminder',
        body: result.body ?? 'Time to wind down.',
        priority: result.urgency == 'urgent'
            ? Priority.high
            : Priority.defaultPriority,
      );
    }
  }

  // ─────────────────────────────────────────────
  // STRESS CHECK
  // ─────────────────────────────────────────────

  static Future<void> _checkStress(WellnessContext ctx) async {
    final result = await WellnessService.calculateStress(ctx);
    if (result.show && result.level == 'high') {
      await _showNotification(
        id: 4001,
        channelId: 'wellness_stress',
        title: result.title ?? '🔴 Busy stretch ahead',
        body: result.body ?? 'Take breaks where you can.',
      );
    }
  }

  // ─────────────────────────────────────────────
  // HELPER — show notification
  // ─────────────────────────────────────────────

  static Future<void> _showNotification({
    required int id,
    required String channelId,
    required String title,
    required String body,
    Priority priority = Priority.defaultPriority,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId,
      importance: Importance.defaultImportance,
      priority: priority,
      showWhen: true,
    );

    await _notifications.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  // ─────────────────────────────────────────────
  // DISMISS HELPERS (call from UI)
  // ─────────────────────────────────────────────

  static Future<void> dismissHydration() async {
    await WellnessService.dismissReminder('hydration');
    await _notifications.cancel(1001);
  }

  static Future<void> dismissSleep() async {
    await WellnessService.dismissReminder('sleep');
    await _notifications.cancel(3001);
  }

  static Future<void> dismissMeal(String mealType) async {
    await WellnessService.dismissReminder('meal_$mealType');
  }
}