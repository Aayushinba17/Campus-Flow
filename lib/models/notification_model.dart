class AppNotification {
  final String? id;
  final String? title;
  final String? body;
  final String? sourceApp;
  final int priority;       // 1-5
  final String? category;   // 'academic', 'social', 'promotional', etc.
  final String? timestamp;
  final bool isRead;
  final String? extractedDeadline;

  AppNotification({
    this.id, this.title, this.body, this.sourceApp,
    this.priority = 2, this.category, this.timestamp,
    this.isRead = false, this.extractedDeadline,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['notification_id'] ?? json['id'],
    title: json['title'] ?? json['sender'],
    body: json['body'] ?? json['text'],
    sourceApp: json['source_app'],
    priority: json['priority'] ?? 2,
    category: json['category'],
    timestamp: json['timestamp'],
    isRead: json['is_read'] == true,
    extractedDeadline: json['extracted_deadline'],
  );

  Map<String, dynamic> toJson() => {
    'title': title, 'body': body, 'source_app': sourceApp,
    'priority': priority, 'category': category,
    'timestamp': timestamp ?? DateTime.now().toIso8601String(),
  };

  bool get isUrgent => priority >= 4;
  bool get isAcademic => category == 'academic';
}
