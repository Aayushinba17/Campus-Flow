import 'package:flutter/material.dart';

class UsageHeatmap extends StatelessWidget {
  final Map<String, dynamic> heatmapData;

  const UsageHeatmap({super.key, required this.heatmapData});

  @override
  Widget build(BuildContext context) {
    final daily = heatmapData['heatmap'] as Map<String, dynamic>? ?? {};
    if (daily.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: Text('No usage data yet', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      );
    }

    final max = daily.values.fold<double>(1, (m, v) => (v as num).toDouble() > m ? (v).toDouble() : m);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Heatmap grid
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: daily.entries.map((entry) {
          final val = (entry.value as num).toDouble();
          final intensity = (val / max).clamp(0.1, 1.0);
          return Column(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Color.lerp(
                  const Color(0xFFE8592B).withValues(alpha: 0.1),
                  const Color(0xFFE8592B),
                  intensity,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: Text(
                '${val.toInt()}',
                style: TextStyle(
                  color: intensity > 0.5 ? Colors.white : const Color(0xFFE8592B),
                  fontSize: 10, fontWeight: FontWeight.bold,
                ),
              )),
            ),
            const SizedBox(height: 4),
            Text(
              entry.key.length >= 3 ? entry.key.substring(0, 3) : entry.key,
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
            ),
          ]);
        }).toList(),
      ),
      const SizedBox(height: 12),
      // Legend
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('Less ', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ...List.generate(5, (i) => Container(
          width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: Color.lerp(const Color(0xFFE8592B).withValues(alpha: 0.1), const Color(0xFFE8592B), (i + 1) / 5),
            borderRadius: BorderRadius.circular(3),
          ),
        )),
        Text(' More', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ]),
    ]);
  }
}
