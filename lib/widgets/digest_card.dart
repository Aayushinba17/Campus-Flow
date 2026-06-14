import 'package:flutter/material.dart';

class DigestCard extends StatelessWidget {
  final Map<String, dynamic> digest;
  final VoidCallback? onRefresh;

  const DigestCard({super.key, required this.digest, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFFE8592B).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            const Text('AI Morning Briefing',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
            const Spacer(),
            if (onRefresh != null)
              GestureDetector(
                onTap: onRefresh,
                child: const Icon(Icons.refresh, color: Colors.white54, size: 18),
              ),
          ]),
          const SizedBox(height: 12),
          Text(digest['greeting'] ?? 'Good morning!',
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),

          if ((digest['urgent_items'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 14),
            ...((digest['urgent_items'] as List).take(4).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(item.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4))),
              ]),
            ))),
          ],

          if (digest['wellness_tip'] != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                const Icon(Icons.lightbulb_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(digest['wellness_tip'],
                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3))),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
