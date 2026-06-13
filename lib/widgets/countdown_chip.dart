import 'package:flutter/material.dart';

class CountdownChip extends StatelessWidget {
  final String label;
  final int daysLeft;
  final Color? color;

  const CountdownChip({
    super.key,
    required this.label,
    required this.daysLeft,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? _getColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: chipColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text(
            '$daysLeft',
            style: TextStyle(color: chipColor, fontWeight: FontWeight.bold, fontSize: 16),
          )),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(daysLeft == 1 ? 'day left' : 'days left',
            style: TextStyle(color: chipColor, fontSize: 10, fontWeight: FontWeight.w500)),
          Text(label, style: TextStyle(
            color: chipColor.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  Color _getColor() {
    if (daysLeft <= 1) return Colors.red;
    if (daysLeft <= 3) return const Color(0xFFE8592B);
    if (daysLeft <= 7) return const Color(0xFFD97706);
    return const Color(0xFF059669);
  }
}
