// import 'package:flutter/material.dart';
// import 'dart:async';
// import '../services/api_service.dart';

// class WellnessScreen extends StatefulWidget {
//   const WellnessScreen({super.key});

//   @override
//   State<WellnessScreen> createState() => _WellnessScreenState();
// }

// class _WellnessScreenState extends State<WellnessScreen> {
//   final _api = ApiService();

//   Map<String, dynamic>? _weeklySummary;
//   Map<String, dynamic>? _stressDensity;
//   bool _loading = true;

//   // Pomodoro state
//   bool _pomodoroRunning = false;
//   int _pomodoroSeconds = 25 * 60;
//   Timer? _pomodoroTimer;
//   int _pomodoroCount = 0;

//   @override
//   void initState() { super.initState(); _loadData(); }

//   @override
//   void dispose() { _pomodoroTimer?.cancel(); super.dispose(); }

//   Future<void> _loadData() async {
//     setState(() => _loading = true);
//     try {
//       final results = await Future.wait([
//         _api.getWeeklySummary(),
//         _api.getStressDensity(),
//       ]);
//       setState(() {
//         _weeklySummary = results[0];
//         _stressDensity = results[1];
//         _loading = false;
//       });
//     } catch (e) { setState(() => _loading = false); }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: const Color(0xFFF5F5F7),
//       appBar: AppBar(
//         title: const Text('Wellness', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
//         backgroundColor: Colors.white, elevation: 0,
//       ),
//       body: _loading
//           ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)))
//           : RefreshIndicator(
//               onRefresh: _loadData,
//               child: ListView(padding: const EdgeInsets.all(16), children: [
//                 // Pomodoro Timer
//                 _pomodoroCard(),
//                 const SizedBox(height: 16),

//                 // Stress Density
//                 if (_stressDensity != null) ...[
//                   _stressDensityCard(),
//                   const SizedBox(height: 16),
//                 ],

//                 // Weekly Summary
//                 if (_weeklySummary != null) ...[
//                   _weeklySummaryCard(),
//                   const SizedBox(height: 16),
//                 ],

//                 // Wellness checks
//                 _wellnessChecksSection(),
//                 const SizedBox(height: 80),
//               ]),
//             ),
//     );
//   }

//   // ═══════════════════════════════════════════════════════════════════════
//   //  POMODORO TIMER
//   // ═══════════════════════════════════════════════════════════════════════

//   Widget _pomodoroCard() {
//     final minutes = _pomodoroSeconds ~/ 60;
//     final seconds = _pomodoroSeconds % 60;
//     final progress = 1.0 - (_pomodoroSeconds / (25 * 60));

//     return Container(
//       padding: const EdgeInsets.all(24),
//       decoration: BoxDecoration(
//         gradient: LinearGradient(
//           colors: _pomodoroRunning
//               ? [const Color(0xFFE8592B), const Color(0xFFFF8C5A)]
//               : [const Color(0xFF1A1A2E), const Color(0xFF2D2D44)],
//           begin: Alignment.topLeft, end: Alignment.bottomRight,
//         ),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Column(children: [
//         Row(children: [
//           const Icon(Icons.timer_outlined, color: Colors.white70, size: 18),
//           const SizedBox(width: 6),
//           const Text('Focus Timer', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
//           const Spacer(),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.15),
//               borderRadius: BorderRadius.circular(12),
//             ),
//             child: Text('$_pomodoroCount sessions',
//               style: const TextStyle(color: Colors.white70, fontSize: 11)),
//           ),
//         ]),
//         const SizedBox(height: 24),

//         // Timer circle
//         SizedBox(
//           width: 160, height: 160,
//           child: Stack(alignment: Alignment.center, children: [
//             SizedBox(
//               width: 160, height: 160,
//               child: CircularProgressIndicator(
//                 value: progress,
//                 strokeWidth: 8,
//                 backgroundColor: Colors.white.withOpacity(0.15),
//                 valueColor: const AlwaysStoppedAnimation(Colors.white),
//               ),
//             ),
//             Column(mainAxisSize: MainAxisSize.min, children: [
//               Text(
//                 '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
//                 style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
//               ),
//               Text(
//                 _pomodoroRunning ? 'Focus time' : 'Ready',
//                 style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
//               ),
//             ]),
//           ]),
//         ),
//         const SizedBox(height: 24),

//         // Controls
//         Row(mainAxisAlignment: MainAxisAlignment.center, children: [
//           // Reset
//           GestureDetector(
//             onTap: _resetPomodoro,
//             child: Container(
//               width: 48, height: 48,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 color: Colors.white.withOpacity(0.15),
//               ),
//               child: const Icon(Icons.refresh, color: Colors.white70, size: 22),
//             ),
//           ),
//           const SizedBox(width: 20),
//           // Play/Pause
//           GestureDetector(
//             onTap: _togglePomodoro,
//             child: Container(
//               width: 64, height: 64,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 color: Colors.white,
//                 boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.3), blurRadius: 16)],
//               ),
//               child: Icon(
//                 _pomodoroRunning ? Icons.pause : Icons.play_arrow,
//                 color: _pomodoroRunning ? const Color(0xFFE8592B) : const Color(0xFF1A1A2E),
//                 size: 32,
//               ),
//             ),
//           ),
//           const SizedBox(width: 20),
//           // Duration options
//           GestureDetector(
//             onTap: _showDurationPicker,
//             child: Container(
//               width: 48, height: 48,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 color: Colors.white.withOpacity(0.15),
//               ),
//               child: const Icon(Icons.tune, color: Colors.white70, size: 22),
//             ),
//           ),
//         ]),
//       ]),
//     );
//   }

//   void _togglePomodoro() {
//     if (_pomodoroRunning) {
//       _pomodoroTimer?.cancel();
//       setState(() => _pomodoroRunning = false);
//     } else {
//       setState(() => _pomodoroRunning = true);
//       _pomodoroTimer = Timer.periodic(const Duration(seconds: 1), (_) {
//         if (_pomodoroSeconds > 0) {
//           setState(() => _pomodoroSeconds--);
//         } else {
//           _pomodoroTimer?.cancel();
//           setState(() {
//             _pomodoroRunning = false;
//             _pomodoroCount++;
//             _pomodoroSeconds = 25 * 60;
//           });
//           // Log session
//           _api.logPomodoroSession({
//             'duration_minutes': 25,
//             'completed': true,
//             'session_number': _pomodoroCount,
//           });
//           // Show completion
//           if (mounted) {
//             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
//               content: Text('🎉 Pomodoro complete! Take a 5-min break.'),
//               backgroundColor: Color(0xFF059669),
//             ));
//           }
//         }
//       });
//     }
//   }

//   void _resetPomodoro() {
//     _pomodoroTimer?.cancel();
//     setState(() { _pomodoroRunning = false; _pomodoroSeconds = 25 * 60; });
//   }

//   void _showDurationPicker() {
//     showModalBottomSheet(
//       context: context, backgroundColor: Colors.transparent,
//       builder: (_) => Container(
//         padding: const EdgeInsets.all(24),
//         decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
//         child: Column(mainAxisSize: MainAxisSize.min, children: [
//           const Text('Focus Duration', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
//           const SizedBox(height: 16),
//           Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
//             _durationOption(15), _durationOption(25), _durationOption(45), _durationOption(60),
//           ]),
//         ]),
//       ),
//     );
//   }

//   Widget _durationOption(int minutes) {
//     final isSelected = _pomodoroSeconds == minutes * 60;
//     return GestureDetector(
//       onTap: () {
//         setState(() => _pomodoroSeconds = minutes * 60);
//         Navigator.pop(context);
//       },
//       child: Container(
//         width: 64, height: 64,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           color: isSelected ? const Color(0xFFE8592B) : const Color(0xFFF5F5F7),
//         ),
//         child: Center(child: Text('$minutes', style: TextStyle(
//           fontSize: 20, fontWeight: FontWeight.bold,
//           color: isSelected ? Colors.white : const Color(0xFF1A1A2E),
//         ))),
//       ),
//     );
//   }

//   // ═══════════════════════════════════════════════════════════════════════
//   //  STRESS DENSITY
//   // ═══════════════════════════════════════════════════════════════════════

//   Widget _stressDensityCard() {
//     final level = _stressDensity!['level'] ?? 'moderate';
//     final colors = {
//       'light': const Color(0xFF059669),
//       'moderate': const Color(0xFFD97706),
//       'heavy': const Color(0xFFE8592B),
//       'very_heavy': Colors.red,
//     };
//     final emojis = {'light': '😌', 'moderate': '😐', 'heavy': '😓', 'very_heavy': '🔥'};
//     final color = colors[level] ?? const Color(0xFFE8592B);

//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.08),
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: color.withOpacity(0.3)),
//       ),
//       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         Row(children: [
//           Text(emojis[level] ?? '😐', style: const TextStyle(fontSize: 24)),
//           const SizedBox(width: 10),
//           Text('Stress Level: ${level.replaceAll('_', ' ').toUpperCase()}',
//             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
//         ]),
//         const SizedBox(height: 8),
//         Text(_stressDensity!['message'] ?? 'Take breaks between tasks',
//           style: TextStyle(fontSize: 13, color: color, height: 1.4)),
//       ]),
//     );
//   }

//   // ═══════════════════════════════════════════════════════════════════════
//   //  WEEKLY SUMMARY
//   // ═══════════════════════════════════════════════════════════════════════

//   Widget _weeklySummaryCard() {
//     final w = _weeklySummary!;
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
//       child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         const Row(children: [
//           Icon(Icons.insights, color: Color(0xFFE8592B), size: 20),
//           SizedBox(width: 8),
//           Text('Weekly Overview', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
//         ]),
//         const SizedBox(height: 16),
//         Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
//           _statColumn(w['total_pomodoros']?.toString() ?? '0', 'Pomodoros', Icons.timer),
//           _statColumn(w['total_focus_hours']?.toString() ?? '0', 'Focus Hrs', Icons.visibility),
//           _statColumn(w['avg_sleep']?.toString() ?? '-', 'Avg Sleep', Icons.bedtime),
//         ]),
//         if (w['summary'] != null) ...[
//           const SizedBox(height: 12),
//           Text(w['summary'], style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4)),
//         ],
//       ]),
//     );
//   }

//   Widget _statColumn(String value, String label, IconData icon) {
//     return Column(children: [
//       Icon(icon, color: const Color(0xFFE8592B), size: 22),
//       const SizedBox(height: 6),
//       Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
//       Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
//     ]);
//   }

//   // ═══════════════════════════════════════════════════════════════════════
//   //  WELLNESS CHECKS
//   // ═══════════════════════════════════════════════════════════════════════

//   Widget _wellnessChecksSection() {
//     return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//       const Text('Wellness Reminders', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
//       const SizedBox(height: 12),
//       _wellnessCheckCard('water', 'Water Reminder', 'Stay hydrated!', Icons.water_drop_outlined, const Color(0xFF2563EB)),
//       const SizedBox(height: 8),
//       _wellnessCheckCard('stretch', 'Stretch Break', 'Move your body', Icons.self_improvement_outlined, const Color(0xFF059669)),
//       const SizedBox(height: 8),
//       _wellnessCheckCard('eye_rest', 'Eye Rest', '20-20-20 rule', Icons.visibility_outlined, const Color(0xFF7C3AED)),
//       const SizedBox(height: 8),

//       // Sleep reminder
//       FutureBuilder<Map<String, dynamic>>(
//         future: _api.getSleepReminder(),
//         builder: (_, snap) {
//           if (!snap.hasData) return const SizedBox.shrink();
//           final sleep = snap.data!;
//           if (sleep['should_remind'] != true) return const SizedBox.shrink();
//           return Container(
//             padding: const EdgeInsets.all(14),
//             decoration: BoxDecoration(
//               color: const Color(0xFF1A1A2E).withOpacity(0.05),
//               borderRadius: BorderRadius.circular(14),
//               border: Border.all(color: const Color(0xFF1A1A2E).withOpacity(0.15)),
//             ),
//             child: Row(children: [
//               const Icon(Icons.bedtime, color: Color(0xFF1A1A2E), size: 20),
//               const SizedBox(width: 12),
//               Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//                 const Text('Time to Wind Down', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
//                 Text(sleep['message'] ?? 'Get some rest',
//                   style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
//               ])),
//             ]),
//           );
//         },
//       ),
//     ]);
//   }

//   Widget _wellnessCheckCard(String type, String title, String subtitle, IconData icon, Color color) {
//     return GestureDetector(
//       onTap: () async {
//         final result = await _api.checkWellnessReminder(type);
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//             content: Text(result['message'] ?? 'Wellness reminder checked!'),
//             backgroundColor: color,
//           ));
//         }
//       },
//       child: Container(
//         padding: const EdgeInsets.all(14),
//         decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
//         child: Row(children: [
//           Container(
//             width: 40, height: 40,
//             decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
//             child: Icon(icon, color: color, size: 20),
//           ),
//           const SizedBox(width: 12),
//           Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
//             Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
//           ])),
//           Icon(Icons.chevron_right, color: Colors.grey.shade300),
//         ]),
//       ),
//     );
//   }
// }













// lib/screens/wellness_screen.dart

import 'package:flutter/material.dart';
import '../models/wellness_model.dart';
import '../services/wellness_service.dart';

class WellnessScreen extends StatefulWidget {
  final WellnessContext ctx;
  const WellnessScreen({super.key, required this.ctx});

  @override
  State<WellnessScreen> createState() => _WellnessScreenState();
}

class _WellnessScreenState extends State<WellnessScreen> {
  int _cupsToday = 0;
  StressResponse? _stress;
  WeeklySummaryResponse? _weeklySummary;
  bool _loadingWeekly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cups = await WellnessService.getCupsToday();
    final stress = await WellnessService.calculateStress(widget.ctx);
    setState(() {
      _cupsToday = cups;
      _stress = stress;
    });
  }

  Future<void> _addCup() async {
    await WellnessService.addCup();
    final cups = await WellnessService.getCupsToday();
    setState(() => _cupsToday = cups);
  }

  Future<void> _loadWeeklySummary() async {
    setState(() => _loadingWeekly = true);
    // screenOnMinutesToday is total screen time; use it as total
    // study time = productivity apps usage (passed from context)
    // leisure = total - study
    final totalMins = widget.ctx.screenOnMinutesToday;
    final studyMins = widget.ctx.studyMinutesToday;
    final leisureMins = (totalMins - studyMins).clamp(0, totalMins);

    final summary = await WellnessService.getWeeklySummary(
      ctx: widget.ctx,
      studyMinutes: studyMins,
      leisureMinutes: leisureMins,
      totalScreenMinutes: totalMins,
    );
    setState(() {
      _weeklySummary = summary;
      _loadingWeekly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Wellness', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stress Density Card ──
            if (_stress != null && _stress!.show) ...[
              _StressDensityCard(stress: _stress!),
              const SizedBox(height: 16),
            ],

            // ── Hydration Card ──
            _HydrationCard(
              cupsToday: _cupsToday,
              onAddCup: _addCup,
            ),
            const SizedBox(height: 16),

            // ── Meal Timing Card ──
            _MealTimingCard(ctx: widget.ctx),
            const SizedBox(height: 16),

            // ── Sleep Reminder Card ──
            _SleepReminderCard(ctx: widget.ctx),
            const SizedBox(height: 16),

            // ── Weekly Summary (Roadmap) ──
            _WeeklySummaryCard(
              summary: _weeklySummary,
              loading: _loadingWeekly,
              onLoad: _loadWeeklySummary,
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────
// STRESS DENSITY CARD
// ─────────────────────────────────────────────

class _StressDensityCard extends StatelessWidget {
  final StressResponse stress;
  const _StressDensityCard({required this.stress});

  Color get _color {
    switch (stress.level) {
      case 'high':
        return const Color(0xFFEF4444);
      case 'medium':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF10B981);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stress.title ?? '',
            style: TextStyle(
              color: _color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            stress.body ?? '',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _StatPill('${stress.breakdown['deadlines'] ?? 0} deadlines', _color),
              const SizedBox(width: 8),
              _StatPill('${stress.breakdown['classes'] ?? 0} classes', _color),
              const SizedBox(width: 8),
              _StatPill('${stress.breakdown['urgent_messages'] ?? 0} urgent', _color),
            ],
          )
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatPill(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }
}


// ─────────────────────────────────────────────
// HYDRATION CARD
// ─────────────────────────────────────────────

class _HydrationCard extends StatelessWidget {
  final int cupsToday;
  final VoidCallback onAddCup;
  const _HydrationCard({required this.cupsToday, required this.onAddCup});

  @override
  Widget build(BuildContext context) {
    final progress = (cupsToday / 8).clamp(0.0, 1.0);
    return _WellnessCard(
      title: '💧 Hydration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$cupsToday / 8 cups',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: onAddCup,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add cup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(8, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.water_drop,
                  size: 20,
                  color: i < cupsToday
                      ? const Color(0xFF3B82F6)
                      : Colors.white12,
                ),
              );
            }),
          ),
          if (cupsToday < 8)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${8 - cupsToday} more cups to reach your daily goal',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '✅ Daily goal reached!',
                style: TextStyle(color: Color(0xFF10B981), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────
// MEAL TIMING CARD
// ─────────────────────────────────────────────

class _MealTimingCard extends StatefulWidget {
  final WellnessContext ctx;
  const _MealTimingCard({required this.ctx});

  @override
  State<_MealTimingCard> createState() => _MealTimingCardState();
}

class _MealTimingCardState extends State<_MealTimingCard> {
  final Map<String, bool?> _mealStatus = {
    'breakfast': null,
    'lunch': null,
    'dinner': null,
  };

  void _markMealDone(String meal) {
    setState(() => _mealStatus[meal] = true);
    WellnessService.dismissReminder('meal_$meal');
  }

  @override
  Widget build(BuildContext context) {
    final meals = {
      'breakfast': ('🍳', widget.ctx.mealTimes['breakfast'] ?? '08:00'),
      'lunch': ('🍱', widget.ctx.mealTimes['lunch'] ?? '13:00'),
      'dinner': ('🍽️', widget.ctx.mealTimes['dinner'] ?? '19:00'),
    };

    return _WellnessCard(
      title: '🍴 Meal Reminders',
      child: Column(
        children: meals.entries.map((entry) {
          final meal = entry.key;
          final emoji = entry.value.$1;
          final time = entry.value.$2;
          final done = _mealStatus[meal] == true;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meal[0].toUpperCase() + meal.substring(1),
                        style: TextStyle(
                          color: done ? Colors.white38 : Colors.white,
                          fontSize: 14,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!done)
                  GestureDetector(
                    onTap: () => _markMealDone(meal),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Done', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ),
                  )
                else
                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}


// ─────────────────────────────────────────────
// SLEEP REMINDER CARD
// ─────────────────────────────────────────────

class _SleepReminderCard extends StatefulWidget {
  final WellnessContext ctx;
  const _SleepReminderCard({required this.ctx});

  @override
  State<_SleepReminderCard> createState() => _SleepReminderCardState();
}

class _SleepReminderCardState extends State<_SleepReminderCard> {
  String _sleepGoal = '11:00 PM';
  String _wakeGoal = '07:00 AM'; // derived from schedule

  // Calculate recommended sleep from tomorrow's first class
  String _getRecommendedBedtime(String firstClassTime) {
    try {
      final parts = firstClassTime.split(':');
      final classHour = int.parse(parts[0]);
      final classMin = int.parse(parts[1]);
      final wakeTotal = classHour * 60 + classMin - 30; // 30 min to get ready
      final bedTotal = wakeTotal - 450; // 7.5 hrs sleep
      final bedHour = bedTotal ~/ 60 % 24;
      final bedMin = bedTotal % 60;
      final period = bedHour >= 12 ? 'PM' : 'AM';
      final displayHour = bedHour > 12 ? bedHour - 12 : (bedHour == 0 ? 12 : bedHour);
      return '$displayHour:${bedMin.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '11:00 PM';
    }
  }

  // Calculate wake-up goal 30 minutes before first class
  String _getWakeGoal(String firstClassTime) {
    try {
      final parts = firstClassTime.split(':');
      final classHour = int.parse(parts[0]);
      final classMin = int.parse(parts[1]);
      final wakeTotal = classHour * 60 + classMin - 30;
      final wakeHour = (wakeTotal ~/ 60) % 24;
      final wakeMin = wakeTotal % 60;
      final period = wakeHour >= 12 ? 'PM' : 'AM';
      final displayHour = wakeHour > 12 ? wakeHour - 12 : (wakeHour == 0 ? 12 : wakeHour);
      return '$displayHour:${wakeMin.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '07:00 AM';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Find tomorrow's first class (using today's schedule as approximation)
    String? firstClass;
    if (widget.ctx.schedule.isNotEmpty) {
      firstClass = widget.ctx.schedule
          .map((c) => c.time)
          .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      _sleepGoal = _getRecommendedBedtime(firstClass);
      _wakeGoal = _getWakeGoal(firstClass);
    }

    return _WellnessCard(
      title: '🌙 Sleep Tracker',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SleepStatBox(
                  label: 'Bedtime goal',
                  value: _sleepGoal,
                  icon: Icons.bedtime_outlined,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SleepStatBox(
                  label: 'Wake-up goal',
                  value: _wakeGoal,
                  icon: Icons.wb_sunny_outlined,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
          if (firstClass != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Based on your first class at $firstClass tomorrow. Bedtime ensures 7.5h sleep.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SleepStatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SleepStatBox({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────
// WEEKLY SUMMARY CARD (Roadmap feature)
// ─────────────────────────────────────────────

class _WeeklySummaryCard extends StatelessWidget {
  final WeeklySummaryResponse? summary;
  final bool loading;
  final VoidCallback onLoad;

  const _WeeklySummaryCard({
    this.summary,
    required this.loading,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    return _WellnessCard(
      title: '📊 Weekly Wellness Summary',
      badge: 'Roadmap',
      child: summary == null
          ? Column(
              children: [
                const Text(
                  'Get your personalized weekly wellness report — sleep patterns, study/leisure balance, and your busiest day.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : onLoad,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                    ),
                    child: loading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Generate Report'),
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats row
                Row(
                  children: [
                    _WeeklyStatBox(
                      label: 'Avg sleep',
                      value: summary!.avgSleepTime ?? '--',
                      icon: '😴',
                    ),
                    const SizedBox(width: 8),
                    _WeeklyStatBox(
                      label: 'Busiest day',
                      value: summary!.busiestDay ?? '--',
                      icon: '📅',
                    ),
                    const SizedBox(width: 8),
                    _WeeklyStatBox(
                      label: 'Study %',
                      value: '${summary!.studyPct}%',
                      icon: '📚',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Study vs Leisure bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Study vs Leisure',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: summary!.studyPct,
                            child: Container(
                              height: 10,
                              color: const Color(0xFF6C63FF),
                            ),
                          ),
                          Expanded(
                            flex: summary!.leisurePct == 0 ? 1 : summary!.leisurePct,
                            child: Container(
                              height: 10,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        _LegendDot(color: Color(0xFF6C63FF), label: 'Study'),
                        SizedBox(width: 12),
                        _LegendDot(color: Color(0xFF10B981), label: 'Leisure'),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // AI Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    summary!.aiSummary,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _WeeklyStatBox extends StatelessWidget {
  final String label;
  final String value;
  final String icon;

  const _WeeklyStatBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                )),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}


// ─────────────────────────────────────────────
// SHARED CARD WRAPPER
// ─────────────────────────────────────────────

class _WellnessCard extends StatelessWidget {
  final String title;
  final Widget child;
  final String? badge;

  const _WellnessCard({
    required this.title,
    required this.child,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (badge != null) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                        color: Color(0xFFF59E0B), fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}