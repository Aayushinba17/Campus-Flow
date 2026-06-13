class WellnessData {
  final int totalPomodoros;
  final double totalFocusHours;
  final double avgSleep;
  final String? summary;
  final List<String> recommendations;

  WellnessData({
    this.totalPomodoros = 0, this.totalFocusHours = 0,
    this.avgSleep = 0, this.summary, this.recommendations = const [],
  });

  factory WellnessData.fromJson(Map<String, dynamic> json) => WellnessData(
    totalPomodoros: json['total_pomodoros'] ?? 0,
    totalFocusHours: (json['total_focus_hours'] as num?)?.toDouble() ?? 0,
    avgSleep: (json['avg_sleep'] as num?)?.toDouble() ?? 0,
    summary: json['summary'],
    recommendations: (json['recommendations'] as List?)?.map((e) => e.toString()).toList() ?? [],
  );
}

class StressDensity {
  final String level;  // 'light', 'moderate', 'heavy', 'very_heavy'
  final String message;
  final bool showAlert;

  StressDensity({required this.level, required this.message, this.showAlert = false});

  factory StressDensity.fromJson(Map<String, dynamic> json) => StressDensity(
    level: json['level'] ?? 'moderate',
    message: json['message'] ?? 'Stay balanced!',
    showAlert: json['show_alert'] == true,
  );
}

class PomodoroSession {
  final int durationMinutes;
  final bool completed;
  final int sessionNumber;
  final String? subject;

  PomodoroSession({
    required this.durationMinutes, this.completed = true,
    this.sessionNumber = 1, this.subject,
  });

  Map<String, dynamic> toJson() => {
    'duration_minutes': durationMinutes, 'completed': completed,
    'session_number': sessionNumber,
    if (subject != null) 'subject': subject,
  };
}
