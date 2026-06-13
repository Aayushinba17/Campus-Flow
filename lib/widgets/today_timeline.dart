import 'package:flutter/material.dart';

class TodayTimeline extends StatelessWidget {
  final List<dynamic> classes;
  final List<dynamic> events;
  final List<dynamic> dueToday;

  const TodayTimeline({
    super.key,
    required this.classes,
    this.events = const [],
    this.dueToday = const [],
  });

  @override
  Widget build(BuildContext context) {
    final items = [...classes, ...events, ...dueToday];
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.beach_access_outlined, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Text('Nothing scheduled today', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value as Map<String, dynamic>;
        final isLast = i == items.length - 1;
        final isClass = item['type'] == 'class' || item.containsKey('subject');
        final isDeadline = item.containsKey('deadline');
        final isNow = _isNow(item['start_time'], item['end_time']);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isNow ? const Color(0xFFE8592B).withOpacity(0.04) : null,
            border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(children: [
            // Timeline line
            SizedBox(
              width: 20,
              child: Column(children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isNow ? const Color(0xFFE8592B) : Colors.grey.shade300,
                    boxShadow: isNow ? [BoxShadow(color: const Color(0xFFE8592B).withOpacity(0.4), blurRadius: 6)] : null,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            // Icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: (isClass ? const Color(0xFFE8592B) : isDeadline ? Colors.red : Colors.blue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isClass ? Icons.school_outlined : isDeadline ? Icons.assignment_late_outlined : Icons.event_outlined,
                size: 18,
                color: isClass ? const Color(0xFFE8592B) : isDeadline ? Colors.red : Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['subject'] ?? item['title'] ?? 'Event',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                isClass ? '${item['start_time']} – ${item['end_time']} • ${item['room'] ?? ''}'
                    : isDeadline ? 'Due today' : item['start_time'] ?? '',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ])),
            if (isNow)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFE8592B), borderRadius: BorderRadius.circular(6)),
                child: const Text('NOW', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
          ]),
        );
      }).toList()),
    );
  }

  bool _isNow(String? start, String? end) {
    if (start == null || end == null) return false;
    try {
      final now = DateTime.now();
      final sp = start.split(':');
      final ep = end.split(':');
      final s = DateTime(now.year, now.month, now.day, int.parse(sp[0]), int.parse(sp[1]));
      final e = DateTime(now.year, now.month, now.day, int.parse(ep[0]), int.parse(ep[1]));
      return now.isAfter(s) && now.isBefore(e);
    } catch (_) { return false; }
  }
}
