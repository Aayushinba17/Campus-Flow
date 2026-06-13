import 'package:flutter/material.dart';

class TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onStatusChange;
  final VoidCallback? onTap;

  const TaskCard({super.key, required this.task, this.onStatusChange, this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = task['status'] ?? 'todo';
    final priority = task['priority'] ?? 3;
    final isFollowUp = task['is_follow_up'] == true;

    final priorityColors = {
      1: Colors.grey, 2: Colors.blue, 3: const Color(0xFFD97706),
      4: const Color(0xFFE8592B), 5: Colors.red,
    };
    final pColor = priorityColors[priority] ?? const Color(0xFFE8592B);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isFollowUp ? Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)) : null,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
        ),
        child: Row(children: [
          // Status checkbox
          GestureDetector(
            onTap: onStatusChange,
            child: Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status == 'done' ? const Color(0xFF059669) : Colors.transparent,
                border: Border.all(
                  color: status == 'done' ? const Color(0xFF059669) : pColor,
                  width: 2,
                ),
              ),
              child: status == 'done'
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task['title'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14,
                decoration: status == 'done' ? TextDecoration.lineThrough : null,
                color: status == 'done' ? Colors.grey : null,
              )),
            if (task['deadline'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(children: [
                  Icon(Icons.calendar_today, size: 11, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(task['deadline'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ),
          ])),
          // Priority dot
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: pColor)),
        ]),
      ),
    );
  }
}
