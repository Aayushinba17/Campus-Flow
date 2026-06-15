import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _api = ApiService();
  List<dynamic> _notes = [];
  List<dynamic> _searchResults = [];
  bool _loading = true;
  String? _selectedSubject;

  @override
  void initState() { super.initState(); _loadNotes(); }

  Future<void> _loadNotes() async {
    setState(() => _loading = true);
    try {
      _notes = await _api.getNotesList(subject: _selectedSubject);
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.question_answer_outlined, color: Color(0xFFE8592B)),
            onPressed: _showAskSheet, tooltip: 'Ask your notes'),
          IconButton(icon: const Icon(Icons.add_circle_outline, color: Color(0xFFE8592B)),
            onPressed: _showAddNoteSheet, tooltip: 'Add note'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotes,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)))
            : _notes.isEmpty ? _emptyState() : _notesList(),
      ),
    );
  }

  Widget _notesList() {
    // Get unique subjects for filter chips
    final subjects = _notes.map((n) => (n as Map<String, dynamic>)['subject'] ?? 'General').toSet().toList();
    // Check if we are currently searching
    final isSearching = _searchResults.isNotEmpty;
    // Determine which list of notes to display
    final displayNotes = isSearching ? _searchResults : _notes;

    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        decoration: InputDecoration(
          hintText: 'Search your notes by meaning...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: isSearching 
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() => _searchResults = []),
              ) 
            : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.white,
        ),
        onSubmitted: (q) async {
          if (q.trim().isEmpty) {
            setState(() => _searchResults = []);
            return;
          }
          final res = await _api.semanticSearchNotes(q);
          setState(() => _searchResults = res);
        },
      ),
      const SizedBox(height: 16),
      // Subject filter chips
      if (!isSearching && subjects.length > 1) ...[
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: subjects.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              if (i == 0) {
                return FilterChip(
                  label: const Text('All', style: TextStyle(fontSize: 12)),
                  selected: _selectedSubject == null,
                  onSelected: (_) { setState(() => _selectedSubject = null); _loadNotes(); },
                  selectedColor: const Color(0xFFE8592B).withValues(alpha: 0.15),
                  checkmarkColor: const Color(0xFFE8592B),
                );
              }
              final subject = subjects[i - 1] as String;
              return FilterChip(
                label: Text(subject, style: const TextStyle(fontSize: 12)),
                selected: _selectedSubject == subject,
                onSelected: (_) { setState(() => _selectedSubject = subject); _loadNotes(); },
                selectedColor: const Color(0xFFE8592B).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFFE8592B),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],

      // Notes grid
      ...(displayNotes.map((n) {
        final note = n as Map<String, dynamic>;
        final colors = [
          const Color(0xFFE8592B), const Color(0xFF6366F1), const Color(0xFF059669),
          const Color(0xFFD97706), const Color(0xFF2563EB),
        ];
        final colorIndex = (note['subject']?.hashCode ?? 0).abs() % colors.length;
        final accent = colors[colorIndex];

        return GestureDetector(
          onTap: () => _showNoteDetail(note),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border(left: BorderSide(color: accent, width: 4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(note['subject'] ?? 'General',
                    style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                if (isSearching && note['score'] != null)
                  Text('Match Score: ${(note['score'] * 100).toStringAsFixed(0)}%', 
                    style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.bold))
                else
                  Text(note['created_at']?.toString().substring(0, 10) ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 10),
              Text(note['title'] ?? note['summary'] ?? 'Note',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              if (note['summary'] != null && note['title'] != null) ...[
                const SizedBox(height: 6),
                Text(note['summary'], maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4)),
              ],
              if ((note['key_concepts'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children:
                  (note['key_concepts'] as List).take(4).map((c) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(c.toString(), style: const TextStyle(fontSize: 11)),
                  )).toList(),
                ),
              ],
            ]),
          ),
        );
      })),
    ]);
  }

  void _showNoteDetail(Map<String, dynamic> note) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(controller: controller, padding: const EdgeInsets.all(24), children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(note['title'] ?? note['subject'] ?? 'Note',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
            const SizedBox(height: 6),
            Text(note['subject'] ?? 'General',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
            const Divider(height: 24),

            if (note['summary'] != null) ...[
              const Text('Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              MarkdownBody(data: note['summary'] ?? ''),
              const SizedBox(height: 16),
            ],

            if (note['formatted_notes'] != null) ...[
              const Text('Full Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 6),
              MarkdownBody(data: note['formatted_notes'] ?? ''),
              const SizedBox(height: 16),
            ],

            if ((note['key_concepts'] as List?)?.isNotEmpty == true) ...[
              const Text('Key Concepts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children:
                (note['key_concepts'] as List).map((c) => Chip(
                  label: Text(c.toString(), style: const TextStyle(fontSize: 12)),
                  backgroundColor: const Color(0xFFE8592B).withValues(alpha: 0.08),
                )).toList(),
              ),
            ],

            const SizedBox(height: 24),
            // Delete button
            OutlinedButton.icon(
              onPressed: () async {
                await _api.deleteNote(note['note_id'] ?? '');
                if (mounted) { Navigator.pop(context); _loadNotes(); }
              },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Delete Note', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
            ),
          ]),
        ),
      ),
    );
  }

  void _showAddNoteSheet() {
    final textCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Add Note', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: subjectCtrl,
              decoration: const InputDecoration(labelText: 'Subject (e.g. Physics)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: textCtrl, maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Paste or type your lecture notes...',
                border: OutlineInputBorder(), alignLabelWithHint: true,
              )),
            const SizedBox(height: 16),
            Row(
              children: [
                // ── NEW UPLOAD BUTTON ──
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final result = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                        );
                        if (result != null && result.files.single.path != null) {
                          File selectedFile = File(result.files.single.path!);
                          if (mounted) Navigator.pop(context);
                          _showProcessingDialog();
                          await _api.processNoteFile(selectedFile, subject: subjectCtrl.text.isNotEmpty ? subjectCtrl.text : null);
                          if (mounted) Navigator.pop(context);
                          _loadNotes();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('File processed by AI! ✨'), backgroundColor: Color(0xFF059669)));
                          }
                        }
                      } catch (e) {
                        if (mounted) Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.upload_file, color: Color(0xFFE8592B)),
                    label: const Text('Upload File', style: TextStyle(color: Color(0xFFE8592B))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8592B)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // ── EXISTING TEXT PROCESS BUTTON ──
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (textCtrl.text.isNotEmpty) {
                        Navigator.pop(context);
                        _showProcessingDialog();
                        try {
                          await _api.processNoteText(textCtrl.text,
                            subject: subjectCtrl.text.isNotEmpty ? subjectCtrl.text : null);
                          if (mounted) Navigator.pop(context);
                          _loadNotes();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Note processed by AI! ✨'), backgroundColor: Color(0xFF059669)));
                          }
                        } catch (e) {
                          if (mounted) Navigator.pop(context);
                        }
                      }
                    },
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Process Text'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8592B), 
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  void _showAskSheet() {
    final qCtrl = TextEditingController();
    String? answer;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Row(children: [
                Icon(Icons.auto_awesome, color: Color(0xFFE8592B)),
                SizedBox(width: 8),
                Text('Ask Your Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
              const SizedBox(height: 4),
              Text('E.g. "Explain the concept in slide 3" or "What are Newton\'s laws?"',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: TextField(controller: qCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ask a question...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (q) async {
                    if (q.isNotEmpty) {
                      setSheetState(() => answer = 'Thinking...');
                      final result = await _api.askNotes(q, subject: _selectedSubject);
                      setSheetState(() => answer = result['answer'] ?? 'No answer found');
                    }
                  },
                )),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFFE8592B)),
                  onPressed: () async {
                    if (qCtrl.text.isNotEmpty) {
                      setSheetState(() => answer = 'Thinking...');
                      final result = await _api.askNotes(qCtrl.text, subject: _selectedSubject);
                      setSheetState(() => answer = result['answer'] ?? 'No answer found');
                    }
                  },
                ),
              ]),
              if (answer != null) ...[
                const SizedBox(height: 16),
                Flexible(child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8592B).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(child: MarkdownBody(data: answer!)),
                )),
              ],
            ]),
          ),
        );
      }),
    );
  }

  void _showProcessingDialog() {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Row(children: [
          CircularProgressIndicator(color: Color(0xFFE8592B)),
          SizedBox(width: 16), Text('AI processing notes...'),
        ]),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.note_add_outlined, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      const Text('No notes yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Add notes and AI will summarize & create key concepts',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
      const SizedBox(height: 20),
      ElevatedButton.icon(
        onPressed: _showAddNoteSheet,
        icon: const Icon(Icons.add),
        label: const Text('Add First Note'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8592B), foregroundColor: Colors.white),
      ),
    ]),
  );
}
