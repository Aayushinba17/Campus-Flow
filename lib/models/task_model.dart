class TaskItem {
  final String taskId;
  final String title;
  final String status;     // 'pending', 'todo', 'in_progress', 'done'
  final int priority;      // 1-5
  final String? deadline;
  final String? deadlineText;
  final String? type;      // 'assignment', 'reminder', 'follow_up', 'meeting'
  final bool isFollowUp;
  final String? person;    // For follow-ups
  final String? source;    // 'voice_note', 'notification', 'manual'
  final String? createdAt;

  TaskItem({
    required this.taskId, required this.title, required this.status,
    this.priority = 3, this.deadline, this.deadlineText, this.type,
    this.isFollowUp = false, this.person, this.source, this.createdAt,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
    taskId: json['task_id'] ?? '',
    title: json['title'] ?? '',
    status: json['status'] ?? 'todo',
    priority: json['priority'] ?? 3,
    deadline: json['deadline'],
    deadlineText: json['deadline_text'],
    type: json['type'],
    isFollowUp: json['is_follow_up'] == true,
    person: json['person'],
    source: json['source'],
    createdAt: json['created_at'],
  );

  Map<String, dynamic> toJson() => {
    'task_id': taskId, 'title': title, 'status': status,
    'priority': priority, 'deadline': deadline, 'type': type,
    'is_follow_up': isFollowUp, 'person': person, 'source': source,
  };

  bool get isDue {
    if (deadline == null) return false;
    try {
      final dl = DateTime.parse(deadline!);
      return dl.isBefore(DateTime.now().add(const Duration(days: 1)));
    } catch (_) { return false; }
  }
}
