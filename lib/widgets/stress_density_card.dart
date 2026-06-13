import 'package:flutter/material.dart';

class StressDensityCard extends StatelessWidget {
  final Map<String, dynamic> stressData;

  const StressDensityCard({super.key, required this.stressData});

  @override
  Widget build(BuildContext context) {
    final level = stressData['level'] as String? ?? 'moderate';
    final message = stressData['message'] as String? ?? 'Stay balanced!';

    final colors = {
      'light': const Color(0xFF059669),
      'moderate': const Color(0xFFD97706),
      'heavy': const Color(0xFFE8592B),
      'very_heavy': Colors.red,
    };
    final emojis = {'light': '😌', 'moderate': '😐', 'heavy': '😓', 'very_heavy': '🔥'};
    final labels = {'light': 'Light', 'moderate': 'Moderate', 'heavy': 'Heavy', 'very_heavy': 'Overloaded'};
    final color = colors[level] ?? const Color(0xFFE8592B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Text(emojis[level] ?? '😐', style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Stress: ${labels[level] ?? level}',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          const SizedBox(height: 2),
          Text(message, style: TextStyle(fontSize: 12, color: color.withOpacity(0.8), height: 1.3)),
        ])),
      ]),
    );
  }
}
