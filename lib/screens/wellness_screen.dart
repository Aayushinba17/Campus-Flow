import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';

class WellnessScreen extends StatefulWidget {
  const WellnessScreen({super.key});

  @override
  State<WellnessScreen> createState() => _WellnessScreenState();
}

class _WellnessScreenState extends State<WellnessScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _weeklySummary;
  Map<String, dynamic>? _stressDensity;
  bool _loading = true;

  // Pomodoro state
  bool _pomodoroRunning = false;
  int _pomodoroSeconds = 25 * 60;
  Timer? _pomodoroTimer;
  int _pomodoroCount = 0;

  @override
  void initState() { super.initState(); _loadData(); }

  @override
  void dispose() { _pomodoroTimer?.cancel(); super.dispose(); }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getWeeklySummary(),
        _api.getStressDensity(),
      ]);
      setState(() {
        _weeklySummary = results[0];
        _stressDensity = results[1];
        _loading = false;
      });
    } catch (e) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Wellness', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Pomodoro Timer
                _pomodoroCard(),
                const SizedBox(height: 16),

                // Stress Density
                if (_stressDensity != null) ...[
                  _stressDensityCard(),
                  const SizedBox(height: 16),
                ],

                // Weekly Summary
                if (_weeklySummary != null) ...[
                  _weeklySummaryCard(),
                  const SizedBox(height: 16),
                ],

                // Wellness checks
                _wellnessChecksSection(),
                const SizedBox(height: 80),
              ]),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  POMODORO TIMER
  // ═══════════════════════════════════════════════════════════════════════

  Widget _pomodoroCard() {
    final minutes = _pomodoroSeconds ~/ 60;
    final seconds = _pomodoroSeconds % 60;
    final progress = 1.0 - (_pomodoroSeconds / (25 * 60));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _pomodoroRunning
              ? [const Color(0xFFE8592B), const Color(0xFFFF8C5A)]
              : [const Color(0xFF1A1A2E), const Color(0xFF2D2D44)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.timer_outlined, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          const Text('Focus Timer', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$_pomodoroCount sessions',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 24),

        // Timer circle
        SizedBox(
          width: 160, height: 160,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 160, height: 160,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                backgroundColor: Colors.white.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
              ),
              Text(
                _pomodoroRunning ? 'Focus time' : 'Ready',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 24),

        // Controls
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Reset
          GestureDetector(
            onTap: _resetPomodoro,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
              ),
              child: const Icon(Icons.refresh, color: Colors.white70, size: 22),
            ),
          ),
          const SizedBox(width: 20),
          // Play/Pause
          GestureDetector(
            onTap: _togglePomodoro,
            child: Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 16)],
              ),
              child: Icon(
                _pomodoroRunning ? Icons.pause : Icons.play_arrow,
                color: _pomodoroRunning ? const Color(0xFFE8592B) : const Color(0xFF1A1A2E),
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Duration options
          GestureDetector(
            onTap: _showDurationPicker,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.15),
              ),
              child: const Icon(Icons.tune, color: Colors.white70, size: 22),
            ),
          ),
        ]),
      ]),
    );
  }

  void _togglePomodoro() {
    if (_pomodoroRunning) {
      _pomodoroTimer?.cancel();
      setState(() => _pomodoroRunning = false);
    } else {
      setState(() => _pomodoroRunning = true);
      _pomodoroTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_pomodoroSeconds > 0) {
          setState(() => _pomodoroSeconds--);
        } else {
          _pomodoroTimer?.cancel();
          setState(() {
            _pomodoroRunning = false;
            _pomodoroCount++;
            _pomodoroSeconds = 25 * 60;
          });
          // Log session
          _api.logPomodoroSession({
            'duration_minutes': 25,
            'completed': true,
            'session_number': _pomodoroCount,
          });
          // Show completion
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('🎉 Pomodoro complete! Take a 5-min break.'),
              backgroundColor: Color(0xFF059669),
            ));
          }
        }
      });
    }
  }

  void _resetPomodoro() {
    _pomodoroTimer?.cancel();
    setState(() { _pomodoroRunning = false; _pomodoroSeconds = 25 * 60; });
  }

  void _showDurationPicker() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Focus Duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _durationOption(15), _durationOption(25), _durationOption(45), _durationOption(60),
          ]),
        ]),
      ),
    );
  }

  Widget _durationOption(int minutes) {
    final isSelected = _pomodoroSeconds == minutes * 60;
    return GestureDetector(
      onTap: () {
        setState(() => _pomodoroSeconds = minutes * 60);
        Navigator.pop(context);
      },
      child: Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? const Color(0xFFE8592B) : const Color(0xFFF5F5F7),
        ),
        child: Center(child: Text('$minutes', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold,
          color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
        ))),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  STRESS DENSITY
  // ═══════════════════════════════════════════════════════════════════════

  Widget _stressDensityCard() {
    final level = _stressDensity!['level'] ?? 'moderate';
    final colors = {
      'light': const Color(0xFF059669),
      'moderate': const Color(0xFFD97706),
      'heavy': const Color(0xFFE8592B),
      'very_heavy': Colors.red,
    };
    final emojis = {'light': '😌', 'moderate': '😐', 'heavy': '😓', 'very_heavy': '🔥'};
    final color = colors[level] ?? const Color(0xFFE8592B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emojis[level] ?? '😐', style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Text('Stress Level: ${level.replaceAll('_', ' ').toUpperCase()}',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
        ]),
        const SizedBox(height: 8),
        Text(_stressDensity!['message'] ?? 'Take breaks between tasks',
          style: TextStyle(fontSize: 13, color: color, height: 1.4)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  WEEKLY SUMMARY
  // ═══════════════════════════════════════════════════════════════════════

  Widget _weeklySummaryCard() {
    final w = _weeklySummary!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.insights, color: Color(0xFFE8592B), size: 20),
          SizedBox(width: 8),
          Text('Weekly Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _statColumn(w['total_pomodoros']?.toString() ?? '0', 'Pomodoros', Icons.timer),
          _statColumn(w['total_focus_hours']?.toString() ?? '0', 'Focus Hrs', Icons.visibility),
          _statColumn(w['avg_sleep']?.toString() ?? '-', 'Avg Sleep', Icons.bedtime),
        ]),
        if (w['summary'] != null) ...[
          const SizedBox(height: 12),
          Text(w['summary'], style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4)),
        ],
      ]),
    );
  }

  Widget _statColumn(String value, String label, IconData icon) {
    return Column(children: [
      Icon(icon, color: const Color(0xFFE8592B), size: 22),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  WELLNESS CHECKS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _wellnessChecksSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Wellness Reminders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 12),
      _wellnessCheckCard('water', 'Water Reminder', 'Stay hydrated!', Icons.water_drop_outlined, const Color(0xFF2563EB)),
      const SizedBox(height: 8),
      _wellnessCheckCard('stretch', 'Stretch Break', 'Move your body', Icons.self_improvement_outlined, const Color(0xFF059669)),
      const SizedBox(height: 8),
      _wellnessCheckCard('eye_rest', 'Eye Rest', '20-20-20 rule', Icons.visibility_outlined, const Color(0xFF7C3AED)),
      const SizedBox(height: 8),

      // Sleep reminder
      FutureBuilder<Map<String, dynamic>>(
        future: _api.getSleepReminder(),
        builder: (_, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final sleep = snap.data!;
          if (sleep['should_remind'] != true) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E).withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1A1A2E).withOpacity(0.15)),
            ),
            child: Row(children: [
              const Icon(Icons.bedtime, color: Color(0xFF1A1A2E), size: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Time to Wind Down', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(sleep['message'] ?? 'Get some rest',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
            ]),
          );
        },
      ),
    ]);
  }

  Widget _wellnessCheckCard(String type, String title, String subtitle, IconData icon, Color color) {
    return GestureDetector(
      onTap: () async {
        final result = await _api.checkWellnessReminder(type);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['message'] ?? 'Wellness reminder checked!'),
            backgroundColor: color,
          ));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey.shade300),
        ]),
      ),
    );
  }
}
