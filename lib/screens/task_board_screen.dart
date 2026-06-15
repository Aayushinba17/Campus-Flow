import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/api_service.dart';

class TaskBoardScreen extends StatefulWidget {
  const TaskBoardScreen({super.key});

  @override
  State<TaskBoardScreen> createState() => _TaskBoardScreenState();
}

class _TaskBoardScreenState extends State<TaskBoardScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _speech = SpeechToText();
  late TabController _tabController;

  List<dynamic> _allTasks = [];
  bool _loading = true;
  bool _listening = false;
  String _liveTranscript = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadTasks();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    try {
      _allTasks = await _api.getAllTasks();
    } catch (_) {}
    setState(() => _loading = false);
  }

  List<dynamic> _filtered(String status) {
    if (status == 'todo') {
      return _allTasks.where((t) => t['status'] == 'todo' || t['status'] == 'pending_confirmation').toList();
    }
    return _allTasks.where((t) => t['status'] == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    final todo = _filtered('todo');
    final inProgress = _filtered('in_progress');
    final done = _filtered('done');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Task Board', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE8592B),
          labelColor: const Color(0xFFE8592B),
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('To Do'), if (todo.isNotEmpty) _badge(todo.length),
            ])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('In Progress'), if (inProgress.isNotEmpty) _badge(inProgress.length),
            ])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('Done'), if (done.isNotEmpty) _badge(done.length),
            ])),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)))
          : TabBarView(
              controller: _tabController,
              children: [
                _taskList(todo, 'todo'),
                _taskList(inProgress, 'in_progress'),
                _taskList(done, 'done'),
              ],
            ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        // Voice note FAB
        FloatingActionButton.small(
          heroTag: 'voice',
          onPressed: _showVoiceSheet,
          backgroundColor: Colors.white,
          child: const Icon(Icons.mic_outlined, color: Color(0xFFE8592B)),
        ),
        const SizedBox(height: 10),
      ]),
    );
  }

  Widget _badge(int count) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFFE8592B), borderRadius: BorderRadius.circular(10)),
    child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  // ═══════════════════════════════════════════════════════════════════════
  //  TASK LIST
  // ═══════════════════════════════════════════════════════════════════════

  Widget _taskList(List<dynamic> tasks, String status) {
    if (tasks.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          status == 'done' ? Icons.celebration_outlined : Icons.task_alt_outlined,
          size: 48, color: Colors.grey.shade300,
        ),
        const SizedBox(height: 12),
        Text(
          status == 'done' ? 'No completed tasks yet' : 'No tasks here',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          status == 'todo' ? 'Use voice notes to add tasks!' : 'Move tasks here to track progress',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      ]));
    }

    return RefreshIndicator(
      onRefresh: _loadTasks,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        itemBuilder: (_, i) => _taskCard(tasks[i] as Map<String, dynamic>, status),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> task, String currentStatus) {
    final isFollowUp = task['is_follow_up'] == true;
    final priority = task['priority'] ?? 3;
    final type = task['type'] ?? 'other';

    final priorityColors = {
      1: Colors.grey, 2: Colors.blue, 3: const Color(0xFFD97706),
      4: const Color(0xFFE8592B), 5: Colors.red,
    };
    final typeIcons = {
      'assignment': Icons.assignment_outlined,
      'reminder': Icons.alarm_outlined,
      'follow_up': Icons.person_search_outlined,
      'meeting': Icons.groups_outlined,
      'other': Icons.task_outlined,
    };
    final pColor = priorityColors[priority] ?? const Color(0xFFE8592B);

    return Dismissible(
      key: Key(task['task_id'] ?? UniqueKey().toString()),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.check_circle, color: Colors.green),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.archive_outlined, color: Colors.red),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          final newStatus = currentStatus == 'todo' ? 'in_progress' : 'done';
          await _api.updateTaskStatus(task['task_id'], newStatus);
          _loadTasks();
          return false;
        }
        return true;
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isFollowUp
              ? Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3))
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Priority dot
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: pColor),
              ),
              const SizedBox(width: 10),
              // Title
              Expanded(child: Text(task['title'] ?? '',
                style: TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14,
                  decoration: currentStatus == 'done' ? TextDecoration.lineThrough : null,
                ))),
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isFollowUp ? const Color(0xFF6366F1).withValues(alpha: 0.1) : pColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(typeIcons[type] ?? Icons.task, size: 12,
                    color: isFollowUp ? const Color(0xFF6366F1) : pColor),
                  const SizedBox(width: 4),
                  Text(isFollowUp ? 'Follow-up' : type,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                      color: isFollowUp ? const Color(0xFF6366F1) : pColor)),
                ]),
              ),
            ]),

            // Deadline
            if (task['deadline'] != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(width: 20),
                Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text('Due: ${task['deadline']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (task['deadline_text'] != null) ...[
                  Text(' (${task['deadline_text']})',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ],
              ]),
            ],

            // Follow-up person
            if (isFollowUp && task['person'] != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const SizedBox(width: 20),
                const Icon(Icons.person_outline, size: 12, color: Color(0xFF6366F1)),
                const SizedBox(width: 4),
                Text('Ask: ${task['person']}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6366F1))),
              ]),
            ],

            // Source badge
            if (task['source'] == 'voice_note') ...[
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(width: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8592B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.mic, size: 10, color: Color(0xFFE8592B)),
                    SizedBox(width: 3),
                    Text('Voice note', style: TextStyle(fontSize: 10, color: Color(0xFFE8592B))),
                  ]),
                ),
              ]),
            ],

            // Action buttons
            if (currentStatus != 'done') ...[
              const SizedBox(height: 10),
              Row(children: [
                const Spacer(),
                if (currentStatus == 'todo')
                  _actionBtn('Start', Icons.play_arrow, const Color(0xFF059669), () async {
                    await _api.updateTaskStatus(task['task_id'], 'in_progress');
                    _loadTasks();
                  }),
                if (currentStatus == 'in_progress')
                  _actionBtn('Done', Icons.check, const Color(0xFF059669), () async {
                    await _api.updateTaskStatus(task['task_id'], 'done');
                    _loadTasks();
                  }),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  VOICE NOTE TO TASKS
  // ═══════════════════════════════════════════════════════════════════════

  void _showVoiceSheet() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('Voice Note → Tasks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 4),
            Text('Speak naturally — AI extracts tasks & follow-ups',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 24),

            // Mic button
            GestureDetector(
              onTap: () => _toggleListening(setSheetState),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: _listening ? 100 : 80,
                height: _listening ? 100 : 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _listening
                        ? [Colors.red, Colors.red.shade700]
                        : [const Color(0xFFE8592B), const Color(0xFFFF8C5A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_listening ? Colors.red : const Color(0xFFE8592B)).withValues(alpha: 0.4),
                      blurRadius: _listening ? 30 : 15,
                    ),
                  ],
                ),
                child: Icon(
                  _listening ? Icons.stop : Icons.mic,
                  color: Colors.white, size: _listening ? 40 : 32,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              _listening ? 'Listening...' : 'Tap to start',
              style: TextStyle(
                color: _listening ? Colors.red : Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),

            // Live transcript
            if (_liveTranscript.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_liveTranscript,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5)),
              ),
            ],

            const SizedBox(height: 12),
            Text('Example: "Remind me to submit physics by Thursday\nand ask sir about the lab practical"',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            const SizedBox(height: 20),
          ]),
        );
      }),
    );
  }

  Future<void> _toggleListening(StateSetter setSheetState) async {
    if (_listening) {
      _speech.stop();
      setSheetState(() => _listening = false);

      if (_liveTranscript.isNotEmpty) {
        Navigator.pop(context);
        _processVoiceNote(_liveTranscript);
      }
    } else {
      final available = await _speech.initialize();
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone not available')));
        }
        return;
      }

      setSheetState(() { _listening = true; _liveTranscript = ''; });

      _speech.listen(
        onResult: (result) {
          setSheetState(() => _liveTranscript = result.recognizedWords);
          if (result.finalResult) {
            setSheetState(() => _listening = false);
            Navigator.pop(context);
            _processVoiceNote(result.recognizedWords);
          }
        },
        listenOptions: SpeechListenOptions(listenFor: const Duration(seconds: 30)),
      );
    }
  }

  Future<void> _processVoiceNote(String text) async {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Row(children: [
          CircularProgressIndicator(color: Color(0xFFE8592B)),
          SizedBox(width: 16), Text('AI extracting tasks...'),
        ]),
      ),
    );

    try {
      final result = await _api.processVoiceNote(text);
      if (mounted) Navigator.pop(context);

      final tasksCount = result['tasks_extracted'] ?? 0;
      final followUpsCount = result['follow_ups_extracted'] ?? 0;
      final total = tasksCount + followUpsCount;

      _loadTasks();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $total items extracted: $tasksCount tasks + $followUpsCount follow-ups'),
          backgroundColor: const Color(0xFF059669),
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }

    setState(() => _liveTranscript = '');
  }
}
