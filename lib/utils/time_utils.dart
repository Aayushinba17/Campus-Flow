import 'package:intl/intl.dart';

class TimeUtils {
  /// Format time string "HH:mm" to "h:mm a" (e.g. "14:30" → "2:30 PM")
  static String format12h(String time24) {
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final dt = DateTime(2000, 1, 1, hour, minute);
      return DateFormat('h:mm a').format(dt);
    } catch (_) { return time24; }
  }

  /// Get relative time string ("2h ago", "5m ago", "Just now")
  static String timeAgo(String isoTimestamp) {
    if (isoTimestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTimestamp);
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('MMM d').format(dt);
    } catch (_) { return ''; }
  }

  /// Check if a time string is currently happening
  static bool isNow(String? startTime, String? endTime) {
    if (startTime == null || endTime == null) return false;
    try {
      final now = DateTime.now();
      final sp = startTime.split(':');
      final ep = endTime.split(':');
      final start = DateTime(now.year, now.month, now.day, int.parse(sp[0]), int.parse(sp[1]));
      final end = DateTime(now.year, now.month, now.day, int.parse(ep[0]), int.parse(ep[1]));
      return now.isAfter(start) && now.isBefore(end);
    } catch (_) { return false; }
  }

  /// Get today's date as "yyyy-MM-dd"
  static String todayStr() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// Get formatted date ("Monday, 15 June")
  static String formatDate(DateTime dt) => DateFormat('EEEE, d MMMM').format(dt);

  /// Get greeting based on time of day
  static String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Calculate minutes until a given time
  static int minutesUntil(String time24) {
    try {
      final parts = time24.split(':');
      final now = DateTime.now();
      final target = DateTime(now.year, now.month, now.day, int.parse(parts[0]), int.parse(parts[1]));
      return target.difference(now).inMinutes;
    } catch (_) { return 0; }
  }

  /// Calculate days between two dates
  static int daysBetween(String date1, String date2) {
    try {
      final d1 = DateTime.parse(date1);
      final d2 = DateTime.parse(date2);
      return d2.difference(d1).inDays;
    } catch (_) { return 0; }
  }

  /// Days until a deadline from today
  static int daysUntil(String dateStr) {
    try {
      final target = DateTime.parse(dateStr);
      final today = DateTime.now();
      return target.difference(DateTime(today.year, today.month, today.day)).inDays;
    } catch (_) { return 0; }
  }
}
