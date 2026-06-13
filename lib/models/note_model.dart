class NoteItem {
  final String noteId;
  final String? title;
  final String? subject;
  final String? summary;
  final String? formattedNotes;
  final List<String> keyConcepts;
  final String? createdAt;

  NoteItem({
    required this.noteId, this.title, this.subject,
    this.summary, this.formattedNotes,
    this.keyConcepts = const [], this.createdAt,
  });

  factory NoteItem.fromJson(Map<String, dynamic> json) => NoteItem(
    noteId: json['note_id'] ?? '',
    title: json['title'],
    subject: json['subject'],
    summary: json['summary'],
    formattedNotes: json['formatted_notes'],
    keyConcepts: (json['key_concepts'] as List?)?.map((e) => e.toString()).toList() ?? [],
    createdAt: json['created_at'],
  );

  Map<String, dynamic> toJson() => {
    'note_id': noteId, 'title': title, 'subject': subject,
    'summary': summary, 'formatted_notes': formattedNotes,
    'key_concepts': keyConcepts,
  };
}
