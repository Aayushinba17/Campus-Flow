import 'package:flutter/material.dart';

class WellnessNudge extends StatelessWidget {
  final String type;
  final String message;
  final VoidCallback? onDismiss;
  final VoidCallback? onAction;

  const WellnessNudge({
    super.key,
    required this.type,
    required this.message,
    this.onDismiss,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: config['color'].withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: config['color'].withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: config['color'].withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(config['icon'] as IconData, color: config['color'] as Color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(config['title'] as String,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: config['color'] as Color)),
          const SizedBox(height: 2),
          Text(message, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ])),
        if (onDismiss != null)
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, size: 18, color: Colors.grey.shade400),
          ),
      ]),
    );
  }

  Map<String, dynamic> _getConfig() {
    switch (type) {
      case 'water':
        return {'icon': Icons.water_drop_outlined, 'color': const Color(0xFF2563EB), 'title': '💧 Water Reminder'};
      case 'stretch':
        return {'icon': Icons.self_improvement, 'color': const Color(0xFF059669), 'title': '🧘 Stretch Break'};
      case 'eye_rest':
        return {'icon': Icons.visibility, 'color': const Color(0xFF7C3AED), 'title': '👁 Eye Rest'};
      case 'sleep':
        return {'icon': Icons.bedtime, 'color': const Color(0xFF1A1A2E), 'title': '😴 Sleep Time'};
      default:
        return {'icon': Icons.favorite, 'color': const Color(0xFFE8592B), 'title': '❤️ Wellness'};
    }
  }
}
