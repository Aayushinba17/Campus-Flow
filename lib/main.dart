import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'utils/constants.dart';
import 'services/api_service.dart';
import 'services/proactive_alert_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'services/wellness_notification_manager.dart';
import 'models/wellness_model.dart';
import 'services/location_service.dart';
import 'package:intl/intl.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ── WorkManager background task dispatcher ────────────────────────────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final api = ApiService();
    final alertService = ProactiveAlertService();
    switch (task) {
      case AppConstants.taskClassroomSync:
        if (await api.isClassroomConnected()) {
          await api.syncClassroom();
          await api.syncClassroomAnnouncements();
        }
        break;
      case AppConstants.taskDigest:
        await api.getMorningDigest();
        break;
      case AppConstants.taskNotifSync:
        // Notification sync handled by native service
        break;
      case AppConstants.taskUsageSync:
        // Usage stats synced from usage_stats_service
        break;
      case 'proactive_alert_check':
        // Fires every 15 minutes — checks all pending alerts
        await alertService.checkAndFirePendingAlerts();
        break;
      case 'deadline_proximity_check':
        // Fires every 6 hours — deep deadline scan
        await alertService.checkDeadlines(hoursAhead: 24);
        break;
      case 'location_zone_check':
        await LocationService.updateCurrentZone();
        break;
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Init local notifications ────────────────────────────────────────── 
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios     = DarwinInitializationSettings();
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );

  // ── Init WorkManager ──────────────────────────────────────────────────
  await Workmanager().initialize(callbackDispatcher);

  // ── Schedule recurring background jobs ────────────────────────────────
  await Workmanager().registerPeriodicTask(
    AppConstants.taskNotifSync,
    AppConstants.taskNotifSync,
    frequency: const Duration(minutes: 30),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  await Workmanager().registerPeriodicTask(
  AppConstants.taskClassroomSync,
    AppConstants.taskClassroomSync,
    frequency: const Duration(hours: 3),  // Google Classroom changes slowly
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  // Init proactive alert service
  final alertService = ProactiveAlertService();
  await alertService.init();

  // Register periodic alert check
  await Workmanager().registerPeriodicTask(
    'proactive_alert_check',
    'proactive_alert_check',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  await Workmanager().registerPeriodicTask(
    'deadline_proximity_check',
    'deadline_proximity_check',
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );

  // Register location zone check
  await Workmanager().registerPeriodicTask(
  'location_zone_check',
  'location_zone_check',
  frequency: const Duration(minutes: 30),
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
);

  // Init notification channels once at startup
  await WellnessNotificationManager.init();

  runApp(const CampusFlowApp());
}

// ── Main App Widget (StatefulWidget for wellness timer lifecycle) ────────
class CampusFlowApp extends StatefulWidget {
  const CampusFlowApp({super.key});

  @override
  State<CampusFlowApp> createState() => _CampusFlowAppState();
}

class _CampusFlowAppState extends State<CampusFlowApp>
    with WidgetsBindingObserver {
  Timer? _wellnessTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Run wellness checks every 30 minutes while app is open
    _wellnessTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _runWellnessChecks();
    });

    // Also run immediately on start (with small delay for init)
    Future.delayed(const Duration(seconds: 5), _runWellnessChecks);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Run checks whenever app comes to foreground
    if (state == AppLifecycleState.resumed) {
      _runWellnessChecks();
    }
  }

  Future<void> _runWellnessChecks() async {
  final api = ApiService();
  try {
    // Pull real schedule for today
    final today = await api.getTodayView();
    final classes = (today['classes'] as List? ?? [])
        .map((c) => ScheduleClassItem(
              time: c['start_time'] ?? '',
              subject: c['subject'] ?? 'Class',
              room: c['room'] ?? '',
            ))
        .toList();

    // Pull real deadline count (next 48h)
    final deadlines = await api.getExtractedDeadlines(daysAhead: 2);

    // Pull real notification stats
    final stats = await api.getNotificationStats();
    final unreadUrgent = (stats['urgent_count'] as int?) ?? 0;
    final screenOnMins = (stats['screen_on_minutes_today'] as int?) ?? 0;

    final ctx = WellnessContext(
      schedule: classes,
      deadlinesIn48h: deadlines.length,
      unreadUrgentMessages: unreadUrgent,
      screenOnMinutesToday: screenOnMins,
      dateLabel: DateFormat('EEEE').format(DateTime.now()),
    );

    // Tomorrow's first class
    String? tomorrowFirstClass;
    try {
      final sched = await api.getSchedule();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
      final tomorrowDay = days[tomorrow.weekday - 1];
      final tomorrowClasses = (sched['classes'] as List? ?? [])
          .where((c) => c['day'] == tomorrowDay).toList();
      if (tomorrowClasses.isNotEmpty) {
        tomorrowClasses.sort((a, b) => (a['start_time'] ?? '').compareTo(b['start_time'] ?? ''));
        tomorrowFirstClass = tomorrowClasses.first['start_time'];
      }
    } catch (_) {}

    await WellnessNotificationManager.runChecks(
      ctx: ctx,
      tomorrowFirstClass: tomorrowFirstClass ?? '09:00',
      screenActive: true,
    );
  } catch (e) {
    // Don't crash the app if server is unreachable — wellness check is best-effort
    debugPrint('[Wellness] Skipped: $e');
  }
}


  @override
  void dispose() {
    _wellnessTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8592B),   // Campus orange
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1A1A2E),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: const Color(0xFFF8F8F8),
        ),
      ),
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _loading = true;
  bool _onboarded = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _onboarded = prefs.getBool('onboarding_complete') ?? false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFE8592B),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('CampusFlow', style: TextStyle(
                color: Colors.white,
                fontSize: 32, fontWeight: FontWeight.bold,
              )),
              SizedBox(height: 8),
              Text('AI Operating System for Student Life',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
              SizedBox(height: 40),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      );
    }
    return _onboarded ? const HomeScreen() : const OnboardingScreen();
  }
}