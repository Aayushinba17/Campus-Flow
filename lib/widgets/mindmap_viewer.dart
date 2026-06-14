import 'package:flutter/material.dart';

class MindmapViewer extends StatelessWidget {
  final Map<String, dynamic> noteData;

  const MindmapViewer({super.key, required this.noteData});

  @override
  Widget build(BuildContext context) {
    final concepts = (noteData['key_concepts'] as List?) ?? [];
    final subject = noteData['subject'] ?? 'Notes';

    if (concepts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: Text('No concepts extracted yet', style: TextStyle(color: Colors.grey))),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_tree_outlined, color: Color(0xFFE8592B), size: 20),
          const SizedBox(width: 8),
          Text('Key Concepts — $subject',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        const SizedBox(height: 16),

        // Central node
        Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: const Color(0xFFE8592B).withValues(alpha: 0.3), blurRadius: 12)],
          ),
          child: Text(subject, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        )),
        const SizedBox(height: 16),

        // Concept nodes
        Wrap(
          spacing: 8, runSpacing: 8,
          alignment: WrapAlignment.center,
          children: concepts.asMap().entries.map((entry) {
            final colors = [
              const Color(0xFF6366F1), const Color(0xFF059669),
              const Color(0xFFD97706), const Color(0xFF2563EB), const Color(0xFF7C3AED),
            ];
            final color = colors[entry.key % colors.length];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(entry.value.toString(),
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            );
          }).toList(),
        ),
      ]),
    );
  }
}
