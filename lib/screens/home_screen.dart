import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../services/usage_stats_service.dart';
import 'schedule_screen.dart';
import 'notifications_screen.dart';
import 'chat_screen.dart';
import 'notes_screen.dart';
import 'wellness_screen.dart';
import '../models/wellness_model.dart';
import 'routine_screen.dart';
import 'task_board_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final _api = ApiService();

  Map<String, dynamic>? _digest;
  Map<String, dynamic>? _todayView;
  Map<String, dynamic>? _stressDensity;
  bool _loading = true;
  String _userName = 'Student';
  int _screenOnMinutesToday = 0;
  int _studyMinutesToday = 0;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _loadUserName();
    _loadUsageStats();
  }

  Future<void> _loadUsageStats() async {
    try {
      final stats = await UsageStatsService().getDailyStats();
      if (mounted) {
        setState(() {
          _screenOnMinutesToday = stats['total_screen_minutes'] as int? ?? 0;
          _studyMinutesToday = stats['study_minutes'] as int? ?? 0;
        });
      }
    } catch (_) {
      // Usage stats unavailable (permission not granted) — keep defaults
    }
  }
    _loadDashboard();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final name = await UserService.getUserName();
    if (mounted) setState(() => _userName = name);
  }
  Future<void> _loadDashboard() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getMorningDigest(),
        _api.getTodayView(),
        _api.getStressDensity(),
      ]);
      setState(() {
        _digest       = results[0]['digest'] as Map<String, dynamic>?;
        _todayView    = results[1] as Map<String, dynamic>?;
        _stressDensity = results[2] as Map<String, dynamic>?;
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
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildDashboard(),
          const ScheduleScreen(),
          const NotificationsScreen(),
          const ChatScreen(),
          const NotesScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: const Color(0xFFE8592B).withValues(alpha: 0.12),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined),    selectedIcon: Icon(Icons.home),          label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today),label: 'Schedule'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Updates'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Ask'),
          NavigationDestination(icon: Icon(Icons.book_outlined),    selectedIcon: Icon(Icons.book),          label: 'Notes'),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final greeting = _getGreeting();
    final dateStr = DateFormat('EEEE, d MMMM').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      color: const Color(0xFFE8592B),
      child: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.white,
            expandedHeight: 100,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting, $_userName!',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                  Text(dateStr,
                    style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.normal)),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.insights_outlined, color: Color(0xFFE8592B)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutineScreen())),
                tooltip: 'Routine insights',
              ),
              IconButton(
                icon: const Icon(Icons.favorite_outline, color: Color(0xFFE8592B)),
                onPressed: () {
                  // Build WellnessContext from available data
                  final classes = (_todayView?['classes'] as List?) ?? [];
                  final scheduleItems = classes.map((c) {
                    final cls = c as Map<String, dynamic>;
                    return ScheduleClassItem(
                      time: cls['start_time'] ?? '09:00',
                      subject: cls['subject'] ?? '',
                      room: cls['room'] ?? '',
                    );
                  }).toList();
                  final deadlines = (_todayView?['due_today'] as List?) ?? [];
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => WellnessScreen(ctx: WellnessContext(
                      schedule: scheduleItems,
                      deadlinesIn48h: deadlines.length,
                      currentTime: '${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}',
                      dateLabel: DateFormat('EEEE').format(DateTime.now()),
                    )),
                  ));
                },
                tooltip: 'Wellness',
              ),
              IconButton(
                icon: const Icon(Icons.task_alt_outlined, color: Color(0xFFE8592B)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaskBoardScreen())),
                tooltip: 'Tasks',
              ),
              const SizedBox(width: 8),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(delegate: SliverChildListDelegate([
              // ── AI Digest Card ───────────────────────────────
              if (_loading)
                _shimmerCard()
              else if (_digest != null)
                _digestCard()
              else
                _emptyDigestCard(),

              const SizedBox(height: 12),

              // ── Stress density ───────────────────────────────
              if (_stressDensity != null && (_stressDensity!['show_alert'] == true))
                _stressCard(),

              const SizedBox(height: 12),

              // ── Today's timeline ─────────────────────────────
              _sectionTitle('Today'),
              const SizedBox(height: 8),
              if (_todayView != null) _todayTimeline() else _shimmerCard(),

              const SizedBox(height: 12),

              // ── Free slots ───────────────────────────────────
              if (_todayView?['free_slots'] != null &&
                  (_todayView!['free_slots'] as List).isNotEmpty) ...[
                _sectionTitle('Free slots today'),
                const SizedBox(height: 8),
                _freeSlotsRow(),
                const SizedBox(height: 12),
              ],

              // ── Deadlines ────────────────────────────────────
              _sectionTitle('Upcoming deadlines'),
              const SizedBox(height: 8),
              _deadlinesSection(),

              const SizedBox(height: 80),
            ])),
          ),
        ],
      ),
    );
  }

  // ── Cards ─────────────────────────────────────────────────────────────

  Widget _digestCard() {
    final d = _digest!;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.auto_awesome, color: Colors.white70, size: 16),
            SizedBox(width: 6),
            Text('AI Morning Briefing',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 10),
          Text(d['greeting'] ?? 'Good morning!',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          if ((d['urgent_items'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            ...((d['urgent_items'] as List).take(3).map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                const Icon(Icons.priority_high, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Expanded(child: Text(item.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 13))),
              ]),
            ))),
          ],
          if (d['wellness_tip'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.lightbulb_outline, color: Colors.white, size: 14),
                const SizedBox(width: 8),
                Expanded(child: Text(d['wellness_tip'],
                  style: const TextStyle(color: Colors.white, fontSize: 12))),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stressCard() {
    final s = _stressDensity!;
    final level = s['level'] as String? ?? 'moderate';
    final colors = {
      'light':      const Color(0xFF4CAF50),
      'moderate':   const Color(0xFFFF9800),
      'heavy':      const Color(0xFFE8592B),
      'very_heavy': const Color(0xFFD32F2F),
    };
    final color = colors[level] ?? const Color(0xFFE8592B);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(Icons.local_fire_department_outlined, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(s['message'] ?? 'Busy stretch ahead. Take breaks!',
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _todayTimeline() {
    final classes = (_todayView!['classes'] as List?) ?? [];
    final events  = (_todayView!['events']  as List?) ?? [];
    final dueToday = (_todayView!['due_today'] as List?) ?? [];
    final items = [...classes, ...events, ...dueToday];

    if (items.isEmpty) {
      return _emptyCard('No classes or events today', Icons.beach_access_outlined);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value as Map<String, dynamic>;
          final isLast = i == items.length - 1;
          final isClass = item['type'] == 'class';
          final isDeadline = item.containsKey('deadline');

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isClass
                    ? const Color(0xFFE8592B).withValues(alpha: 0.1)
                    : isDeadline
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isClass ? Icons.school_outlined : isDeadline ? Icons.assignment_late_outlined : Icons.event_outlined,
                  size: 20,
                  color: isClass ? const Color(0xFFE8592B) : isDeadline ? Colors.red : Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['subject'] ?? item['title'] ?? 'Event',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    isClass
                      ? '${item['start_time']} – ${item['end_time']} • ${item['room'] ?? ''}'
                      : isDeadline ? 'Due today' : item['start_time'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              )),
              if (isClass && item['professor'] != null)
                Text(item['professor'], style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _freeSlotsRow() {
    final slots = (_todayView!['free_slots'] as List?) ?? [];
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slots.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final slot = slots[i] as Map<String, dynamic>;
          return Container(
            width: 140,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${slot['start']} – ${slot['end']}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 2),
                Text('${slot['duration_minutes']} min free',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _deadlinesSection() {
    return FutureBuilder<List<dynamic>>(
      future: _api.getExtractedDeadlines(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return _shimmerCard();
        final deadlines = snap.data ?? [];
        if (deadlines.isEmpty) return _emptyCard('No deadlines found', Icons.check_circle_outline);
        return Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: deadlines.take(5).map((d) {
              final isUrgent = d['deadline'] == DateFormat('yyyy-MM-dd').format(DateTime.now());
              return ListTile(
                leading: Icon(Icons.flag_outlined,
                  color: isUrgent ? Colors.red : const Color(0xFFE8592B)),
                title: Text(d['title'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text('Due: ${d['deadline'] ?? 'Unknown'} • via ${d['source_app'] ?? 'message'}',
                  style: const TextStyle(fontSize: 12)),
                trailing: isUrgent
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: const Text('Today', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  : null,
              );
            }).toList(),
          ),
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  Widget _sectionTitle(String title) => Text(title,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)));

  Widget _shimmerCard() => Container(
    height: 120, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)));

  Widget _emptyCard(String message, IconData icon) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, color: Colors.grey.shade400),
      const SizedBox(width: 10),
      Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
    ]),
  );

  Widget _emptyDigestCard() => GestureDetector(
    onTap: _loadDashboard,
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE8592B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8592B).withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Color(0xFFE8592B)),
          SizedBox(width: 10),
          Text('Tap to generate your morning briefing',
            style: TextStyle(color: Color(0xFFE8592B), fontWeight: FontWeight.w500)),
        ],
      ),
    ),
  );

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning 👋';
    if (hour < 17) return 'Good afternoon 👋';
    return 'Good evening 👋';
  }