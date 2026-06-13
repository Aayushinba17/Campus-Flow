class ScheduleItem {
  final String? subject;
  final String? room;
  final String? professor;
  final String? startTime;
  final String? endTime;
  final String? day;
  final String? type; // 'class', 'event', 'deadline'

  ScheduleItem({
    this.subject, this.room, this.professor,
    this.startTime, this.endTime, this.day, this.type,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
    subject: json['subject'] ?? json['title'],
    room: json['room'],
    professor: json['professor'],
    startTime: json['start_time'],
    endTime: json['end_time'],
    day: json['day'],
    type: json['type'] ?? 'class',
  );

  Map<String, dynamic> toJson() => {
    'subject': subject, 'room': room, 'professor': professor,
    'start_time': startTime, 'end_time': endTime, 'day': day, 'type': type,
  };

  bool get isNow {
    if (startTime == null || endTime == null) return false;
    try {
      final now = DateTime.now();
      final sp = startTime!.split(':');
      final ep = endTime!.split(':');
      final s = DateTime(now.year, now.month, now.day, int.parse(sp[0]), int.parse(sp[1]));
      final e = DateTime(now.year, now.month, now.day, int.parse(ep[0]), int.parse(ep[1]));
      return now.isAfter(s) && now.isBefore(e);
    } catch (_) { return false; }
  }
}

class FreeSlot {
  final String start;
  final String end;
  final int durationMinutes;
  final String? suggestion;

  FreeSlot({required this.start, required this.end, required this.durationMinutes, this.suggestion});

  factory FreeSlot.fromJson(Map<String, dynamic> json) => FreeSlot(
    start: json['start'] ?? '',
    end: json['end'] ?? '',
    durationMinutes: json['duration_minutes'] ?? 0,
    suggestion: json['suggestion'],
  );
}
