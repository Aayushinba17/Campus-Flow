import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/api_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;

  Map<String, dynamic>? _todayView;
  Map<String, dynamic>? _fullSchedule;
  Map<String, dynamic>? _examCountdown;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getTodayView(),
        _api.getSchedule(),
      ]);
      setState(() {
        _todayView = results[0];
        _fullSchedule = results[1];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Schedule', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined, color: Color(0xFFE8592B)),
            onPressed: _uploadTimetable,
            tooltip: 'Upload timetable photo',
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFFE8592B)),
            onPressed: _showAddEventSheet,
            tooltip: 'Add event',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE8592B),
          labelColor: const Color(0xFFE8592B),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Week'),
            Tab(text: 'Exams'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _todayTab(),
          _weekTab(),
          _examsTab(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  TODAY TAB — Unified Today View
  // ═══════════════════════════════════════════════════════════════════════

  Widget _todayTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFE8592B),
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Date header
                _dateHeader(),
                const SizedBox(height: 16),

                // Classes timeline
                _sectionHeader('Classes', Icons.school_outlined, const Color(0xFFE8592B)),
                const SizedBox(height: 8),
                _classesTimeline(),
                const SizedBox(height: 20),

                // Events
                if ((_todayView?['events'] as List?)?.isNotEmpty == true) ...[
                  _sectionHeader('Events', Icons.event_outlined, const Color(0xFF6366F1)),
                  const SizedBox(height: 8),
                  _eventsList(),
                  const SizedBox(height: 20),
                ],

                // Due today
                if ((_todayView?['due_today'] as List?)?.isNotEmpty == true) ...[
                  _sectionHeader('Due Today', Icons.assignment_late_outlined, Colors.red),
                  const SizedBox(height: 8),
                  _dueTodayList(),
                  const SizedBox(height: 20),
                ],

                // Free slots
                _sectionHeader('Free Slots', Icons.coffee_outlined, const Color(0xFF059669)),
                const SizedBox(height: 8),
                _freeSlotsSection(),
                const SizedBox(height: 20),

                // Free slot suggestions button
                _suggestButton(),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _dateHeader() {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(DateFormat('EEEE').format(now),
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(DateFormat('d MMMM yyyy').format(now),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${(_todayView?['classes'] as List?)?.length ?? 0} classes',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }

  Widget _classesTimeline() {
    final classes = (_todayView?['classes'] as List?) ?? [];
    if (classes.isEmpty) return _emptyCard('No classes today', Icons.celebration_outlined);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: classes.asMap().entries.map((entry) {
          final i = entry.key;
          final cls = entry.value as Map<String, dynamic>;
          final isNow = _isCurrentlyHappening(cls['start_time'], cls['end_time']);
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isNow ? const Color(0xFFE8592B).withValues(alpha: 0.05) : null,
              border: i < classes.length - 1
                  ? Border(bottom: BorderSide(color: Colors.grey.shade100))
                  : null,
            ),
            child: Row(children: [
              // Time column
              SizedBox(
                width: 60,
                child: Column(children: [
                  Text(cls['start_time'] ?? '', style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13,
                    color: isNow ? const Color(0xFFE8592B) : Colors.black87)),
                  Text(cls['end_time'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ]),
              ),
              // Timeline dot
              Container(
                width: 12, height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isNow ? const Color(0xFFE8592B) : Colors.grey.shade300,
                  boxShadow: isNow ? [BoxShadow(color: const Color(0xFFE8592B).withValues(alpha: 0.4), blurRadius: 8)] : null,
                ),
              ),
              // Details
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(cls['subject'] ?? 'Class',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                  if (isNow) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE8592B), borderRadius: BorderRadius.circular(8)),
                    child: const Text('NOW', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text('${cls['room'] ?? ''} • ${cls['professor'] ?? ''}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _eventsList() {
    final events = (_todayView?['events'] as List?) ?? [];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: events.map((e) {
        final event = e as Map<String, dynamic>;
        return ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.event, color: Color(0xFF6366F1), size: 20),
          ),
          title: Text(event['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          subtitle: Text(event['start_time'] ?? '', style: const TextStyle(fontSize: 12)),
        );
      }).toList()),
    );
  }

  Widget _dueTodayList() {
    final due = (_todayView?['due_today'] as List?) ?? [];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(children: due.map((d) {
        final item = d as Map<String, dynamic>;
        return ListTile(
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.warning_amber_outlined, color: Colors.red, size: 20),
          ),
          title: Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
          subtitle: Text(item['type'] ?? 'task', style: const TextStyle(fontSize: 12)),
        );
      }).toList()),
    );
  }

  Widget _freeSlotsSection() {
    final slots = (_todayView?['free_slots'] as List?) ?? [];
    if (slots.isEmpty) return _emptyCard('No free slots today', Icons.hourglass_empty_outlined);

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final slot = slots[i] as Map<String, dynamic>;
          return Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                const Icon(Icons.schedule, color: Color(0xFF059669), size: 16),
                const SizedBox(width: 6),
                Text('${slot['start']} – ${slot['end']}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF059669))),
              ]),
              const SizedBox(height: 4),
              Text('${slot['duration_minutes'] ?? 0} min free',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
          );
        },
      ),
    );
  }

  Widget _suggestButton() {
    return GestureDetector(
      onTap: _loadFreeSlotSuggestions,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF6366F1).withValues(alpha: 0.1), const Color(0xFF8B5CF6).withValues(alpha: 0.1)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.2)),
        ),
        child: const Row(children: [
          Icon(Icons.auto_awesome, color: Color(0xFF6366F1), size: 20),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI Task Suggestions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF6366F1))),
            Text('Let AI suggest what to do in free slots', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ])),
          Icon(Icons.chevron_right, color: Color(0xFF6366F1)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  WEEK TAB
  // ═══════════════════════════════════════════════════════════════════════

  Widget _weekTab() {
    final classes = (_fullSchedule?['classes'] as List?) ?? [];
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)));
    if (classes.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.calendar_today_outlined, size: 64, color: Colors.grey),
        const SizedBox(height: 16),
        const Text('No schedule uploaded yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _uploadTimetable,
          icon: const Icon(Icons.upload_file),
          label: const Text('Upload Timetable'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8592B), foregroundColor: Colors.white),
        ),
      ]));
    }

    // Group by day
    final Map<String, List<Map<String, dynamic>>> byDay = {};
    for (final cls in classes) {
      final day = (cls as Map<String, dynamic>)['day'] ?? 'Unknown';
      byDay.putIfAbsent(day, () => []).add(cls);
    }
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: days.where((d) => byDay.containsKey(d)).map((day) {
        final dayClasses = byDay[day]!;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(day, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: dayClasses.map((cls) => ListTile(
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8592B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(
                  '${cls['start_time'] ?? ''}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE8592B)),
                )),
              ),
              title: Text(cls['subject'] ?? '', style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
              subtitle: Text('${cls['room'] ?? ''} • ${cls['professor'] ?? ''}', style: const TextStyle(fontSize: 12)),
              trailing: Text(cls['end_time'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            )).toList()),
          ),
          const SizedBox(height: 16),
        ]);
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  EXAMS TAB
  // ═══════════════════════════════════════════════════════════════════════

  Widget _examsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Add exam button
        GestureDetector(
          onTap: _showAddExamSheet,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(children: [
              Icon(Icons.add_circle_outline, color: Colors.white),
              SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Add Exam', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Get AI countdown & study plan', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        // Countdown display
        if (_examCountdown != null) ...[
          _examCountdownCard(),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _examCountdownCard() {
    final ec = _examCountdown!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.timer_outlined, color: Color(0xFFE8592B)),
          const SizedBox(width: 8),
          Text(ec['exam_name'] ?? 'Exam',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _countdownBox(ec['days_left']?.toString() ?? '0', 'Days'),
          const SizedBox(width: 12),
          _countdownBox(ec['study_hours_available']?.toString() ?? '0', 'Study Hrs'),
        ]),
        if (ec['ai_plan'] != null) ...[
          const SizedBox(height: 12),
          Text(ec['ai_plan'], style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5)),
        ],
      ]),
    );
  }

  Widget _countdownBox(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8592B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFFE8592B))),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _uploadTimetable() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    _showLoadingDialog('Extracting classes...');
    try {
      await _api.uploadTimetableImage(File(picked.path));
      if (mounted) Navigator.pop(context);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timetable uploaded! Classes extracted.'), backgroundColor: Color(0xFF059669)),
      );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
      );
      }
    }
  }

  Future<void> _loadFreeSlotSuggestions() async {
    _showLoadingDialog('AI analyzing free slots...');
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final result = await _api.getFreeSlotSuggestions(today);
      if (mounted) Navigator.pop(context);
      if (mounted) _showSuggestionsSheet(result);
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _showSuggestionsSheet(Map<String, dynamic> suggestions) {
    final items = (suggestions['suggestions'] as List?) ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Center(child: SizedBox(width: 40, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.all(Radius.circular(2)))))),
          const SizedBox(height: 16),
          const Row(children: [
            Icon(Icons.auto_awesome, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text('AI Suggestions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
          const SizedBox(height: 16),
          ...items.take(5).map((s) {
            final suggestion = s as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                tileColor: const Color(0xFF6366F1).withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.lightbulb_outline, color: Color(0xFF6366F1)),
                title: Text(suggestion['task'] ?? suggestion['suggestion'] ?? '', style: const TextStyle(fontSize: 14)),
                subtitle: Text(suggestion['slot'] ?? suggestion['time'] ?? '', style: const TextStyle(fontSize: 12)),
              ),
            );
          }),
        ]),
      ),
    );
  }

  void _showAddEventSheet() {
    final titleCtrl = TextEditingController();
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Add Event', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Event title', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: startCtrl, decoration: const InputDecoration(labelText: 'Start (HH:MM)', border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: endCtrl, decoration: const InputDecoration(labelText: 'End (HH:MM)', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                if (titleCtrl.text.isNotEmpty) {
                  await _api.addManualEvent({
                    'title': titleCtrl.text, 'start_time': startCtrl.text,
                    'end_time': endCtrl.text, 'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  });
                  if (mounted) { Navigator.pop(context); _loadData(); }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8592B), foregroundColor: Colors.white, padding: const EdgeInsets.all(14)),
              child: const Text('Add Event'),
            )),
          ]),
        ),
      ),
    );
  }

  void _showAddExamSheet() {
    final nameCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    DateTime? selectedDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Add Exam', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Exam name (e.g. DSA Mid-Term)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: 'Subject (optional)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final date = await showDatePicker(
                    context: ctx, initialDate: DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setSheetState(() => selectedDate = date);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 18),
                    const SizedBox(width: 10),
                    Text(selectedDate != null ? DateFormat('yyyy-MM-dd').format(selectedDate!) : 'Select exam date'),
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isNotEmpty && selectedDate != null) {
                    Navigator.pop(ctx);
                    _showLoadingDialog('AI generating study plan...');
                    try {
                      final result = await _api.getExamCountdown(
                        nameCtrl.text, DateFormat('yyyy-MM-dd').format(selectedDate!),
                        subject: subjectCtrl.text.isNotEmpty ? subjectCtrl.text : null,
                      );
                      if (mounted) Navigator.pop(context);
                      setState(() => _examCountdown = result);
                    } catch (e) {
                      if (mounted) Navigator.pop(context);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8592B), foregroundColor: Colors.white, padding: const EdgeInsets.all(14)),
                child: const Text('Get AI Study Plan'),
              )),
            ]),
          ),
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _emptyCard(String message, IconData icon) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: Colors.grey.shade400, size: 20),
      const SizedBox(width: 10),
      Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ]),
  );

  bool _isCurrentlyHappening(String? start, String? end) {
    if (start == null || end == null) return false;
    try {
      final now = DateTime.now();
      final startParts = start.split(':');
      final endParts = end.split(':');
      final startTime = DateTime(now.year, now.month, now.day, int.parse(startParts[0]), int.parse(startParts[1]));
      final endTime = DateTime(now.year, now.month, now.day, int.parse(endParts[0]), int.parse(endParts[1]));
      return now.isAfter(startTime) && now.isBefore(endTime);
    } catch (_) { return false; }
  }

  void _showLoadingDialog(String msg) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(children: [
          const CircularProgressIndicator(color: Color(0xFFE8592B)),
          const SizedBox(width: 16),
          Text(msg),
        ]),
      ),
    );
  }
}
