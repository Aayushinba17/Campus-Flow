import 'package:flutter/material.dart';

class FreeSlotCard extends StatelessWidget {
  final Map<String, dynamic> slot;
  final VoidCallback? onTap;

  const FreeSlotCard({super.key, required this.slot, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF059669).withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF059669).withOpacity(0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withOpacity(0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.coffee_outlined, color: Color(0xFF059669), size: 14),
            ),
            const Spacer(),
            Text('${slot['duration_minutes'] ?? 0}m',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669), fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Text('${slot['start'] ?? ''} – ${slot['end'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          Text('Free slot', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          if (slot['suggestion'] != null) ...[
            const SizedBox(height: 6),
            Text(slot['suggestion'], maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
          ],
        ]),
      ),
    );
  }
}
