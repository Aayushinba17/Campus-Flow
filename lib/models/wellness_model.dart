// class WellnessData {
//   final int totalPomodoros;
//   final double totalFocusHours;
//   final double avgSleep;
//   final String? summary;
//   final List<String> recommendations;

//   WellnessData({
//     this.totalPomodoros = 0, this.totalFocusHours = 0,
//     this.avgSleep = 0, this.summary, this.recommendations = const [],
//   });

//   factory WellnessData.fromJson(Map<String, dynamic> json) => WellnessData(
//     totalPomodoros: json['total_pomodoros'] ?? 0,
//     totalFocusHours: (json['total_focus_hours'] as num?)?.toDouble() ?? 0,
//     avgSleep: (json['avg_sleep'] as num?)?.toDouble() ?? 0,
//     summary: json['summary'],
//     recommendations: (json['recommendations'] as List?)?.map((e) => e.toString()).toList() ?? [],
//   );
// }

// class StressDensity {
//   final String level;  // 'light', 'moderate', 'heavy', 'very_heavy'
//   final String message;
//   final bool showAlert;

//   StressDensity({required this.level, required this.message, this.showAlert = false});

//   factory StressDensity.fromJson(Map<String, dynamic> json) => StressDensity(
//     level: json['level'] ?? 'moderate',
//     message: json['message'] ?? 'Stay balanced!',
//     showAlert: json['show_alert'] == true,
//   );
// }

// class PomodoroSession {
//   final int durationMinutes;
//   final bool completed;
//   final int sessionNumber;
//   final String? subject;

//   PomodoroSession({
//     required this.durationMinutes, this.completed = true,
//     this.sessionNumber = 1, this.subject,
//   });

//   Map<String, dynamic> toJson() => {
//     'duration_minutes': durationMinutes, 'completed': completed,
//     'session_number': sessionNumber,
//     if (subject != null) 'subject': subject,
//   };
// }






// lib/models/wellness_models.dart

class ScheduleClassItem {
  final String time;
  final String subject;
  final String room;

  ScheduleClassItem({
    required this.time,
    required this.subject,
    this.room = '',
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'subject': subject,
        'room': room,
      };
}

class WellnessContext {
  final List<ScheduleClassItem> schedule;
  final int screenOnMinutesToday;
  final String? lastScreenOffTime;
  final String currentTime;
  final String dateLabel;
  final int deadlinesIn48h;
  final int unreadUrgentMessages;
  final List<String> dismissedReminders;
  final Map<String, String> mealTimes;
  final List<String> weeklyScreenOffTimes;
  final List<Map<String, dynamic>> weeklyBusyDays;

  WellnessContext({
    this.schedule = const [],
    this.screenOnMinutesToday = 0,
    this.lastScreenOffTime,
    String? currentTime,
    this.dateLabel = '',
    this.deadlinesIn48h = 0,
    this.unreadUrgentMessages = 0,
    this.dismissedReminders = const [],
    Map<String, String>? mealTimes,
    this.weeklyScreenOffTimes = const [],
    this.weeklyBusyDays = const [],
  })  : currentTime = currentTime ?? _nowString(),
        mealTimes = mealTimes ??
            const {
              'breakfast': '08:00',
              'lunch': '13:00',
              'dinner': '19:00',
            };

  static String _nowString() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'schedule': schedule.map((s) => s.toJson()).toList(),
        'screen_on_minutes_today': screenOnMinutesToday,
        'last_screen_off_time': lastScreenOffTime,
        'current_time': currentTime,
        'date_label': dateLabel,
        'deadlines_in_48h': deadlinesIn48h,
        'unread_urgent_messages': unreadUrgentMessages,
        'dismissed_reminders': dismissedReminders,
        'meal_times': mealTimes,
        'weekly_screen_off_times': weeklyScreenOffTimes,
        'weekly_busy_days': weeklyBusyDays,
      };
}

// ─── Response models ───

class HydrationResponse {
  final bool shouldRemind;
  final String? title;
  final String? body;
  final int cupsToday;
  final int cupsRemaining;
  final String reason;
  final int remindInMinutes;

  HydrationResponse({
    required this.shouldRemind,
    this.title,
    this.body,
    this.cupsToday = 0,
    this.cupsRemaining = 8,
    this.reason = '',
    this.remindInMinutes = 90,
  });

  factory HydrationResponse.fromJson(Map<String, dynamic> json) {
    return HydrationResponse(
      shouldRemind: json['should_remind'] ?? false,
      title: json['title'],
      body: json['body'],
      cupsToday: json['cups_today'] ?? 0,
      cupsRemaining: json['cups_remaining'] ?? 8,
      reason: json['reason'] ?? '',
      remindInMinutes: json['remind_in_minutes'] ?? 90,
    );
  }
}

class SleepResponse {
  final bool shouldRemind;
  final String urgency;
  final String? title;
  final String? body;
  final String reason;

  SleepResponse({
    required this.shouldRemind,
    this.urgency = 'normal',
    this.title,
    this.body,
    this.reason = '',
  });

  factory SleepResponse.fromJson(Map<String, dynamic> json) {
    return SleepResponse(
      shouldRemind: json['should_remind'] ?? false,
      urgency: json['urgency'] ?? 'normal',
      title: json['title'],
      body: json['body'],
      reason: json['reason'] ?? '',
    );
  }
}

class MealResponse {
  final bool shouldRemind;
  final String? title;
  final String? body;
  final String mealType;
  final String reason;

  MealResponse({
    required this.shouldRemind,
    this.title,
    this.body,
    this.mealType = '',
    this.reason = '',
  });

  factory MealResponse.fromJson(Map<String, dynamic> json) {
    return MealResponse(
      shouldRemind: json['should_remind'] ?? false,
      title: json['title'],
      body: json['body'],
      mealType: json['meal_type'] ?? '',
      reason: json['reason'] ?? '',
    );
  }
}

class StressResponse {
  final bool show;
  final String level; // "high" | "medium" | "low"
  final String? title;
  final String? body;
  final int score;
  final Map<String, dynamic> breakdown;

  StressResponse({
    required this.show,
    required this.level,
    this.title,
    this.body,
    this.score = 0,
    this.breakdown = const {},
  });

  factory StressResponse.fromJson(Map<String, dynamic> json) {
    return StressResponse(
      show: json['show'] ?? false,
      level: json['level'] ?? 'low',
      title: json['title'],
      body: json['body'],
      score: json['score'] ?? 0,
      breakdown: json['breakdown'] ?? {},
    );
  }
}

class WeeklySummaryResponse {
  final String weekLabel;
  final String? avgSleepTime;
  final String? busiestDay;
  final int studyPct;
  final int leisurePct;
  final String aiSummary;
  final Map<String, dynamic> stats;

  WeeklySummaryResponse({
    this.weekLabel = '',
    this.avgSleepTime,
    this.busiestDay,
    this.studyPct = 0,
    this.leisurePct = 0,
    this.aiSummary = '',
    this.stats = const {},
  });

  factory WeeklySummaryResponse.fromJson(Map<String, dynamic> json) {
    return WeeklySummaryResponse(
      weekLabel: json['week_label'] ?? '',
      avgSleepTime: json['avg_sleep_time'],
      busiestDay: json['busiest_day'],
      studyPct: json['study_pct'] ?? 0,
      leisurePct: json['leisure_pct'] ?? 0,
      aiSummary: json['ai_summary'] ?? '',
      stats: json['stats'] ?? {},
    );
  }
}