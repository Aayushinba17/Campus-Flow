import 'package:flutter/material.dart';

class NotificationTile extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback? onTap;

  const NotificationTile({super.key, required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    final app = notification['source_app'] ?? 'Unknown';
    final priority = notification['priority'] ?? 2;
    final category = notification['category'] ?? 'general';

    final priorityColors = {
      1: Colors.grey, 2: Colors.blue, 3: const Color(0xFFE8592B),
      4: Colors.red, 5: Colors.red,
    };
    final appIcons = {
      'WhatsApp': Icons.chat_bubble, 'Telegram': Icons.send,
      'Gmail': Icons.email, 'SMS': Icons.sms,
      'Instagram': Icons.camera_alt, 'Slack': Icons.tag,
    };
    final color = priorityColors[priority] ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: priority >= 4 ? Border.all(color: Colors.red.withOpacity(0.3)) : null,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // App icon
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(11)),
            child: Icon(appIcons[app] ?? Icons.notifications, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(
                notification['title'] ?? notification['sender'] ?? app,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
              Text(_timeAgo(notification['timestamp'] ?? ''),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]),
            const SizedBox(height: 3),
            Text(notification['body'] ?? notification['text'] ?? '',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4)),
            const SizedBox(height: 6),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                child: Text(app, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ),
              const SizedBox(width: 6),
              if (category != 'general')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                  child: Text(category, style: TextStyle(fontSize: 10, color: color)),
                ),
            ]),
          ])),
        ]),
      ),
    );
  }

  String _timeAgo(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) { return ''; }
  }
}
