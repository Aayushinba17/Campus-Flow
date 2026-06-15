import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:app_usage/app_usage.dart';
import '../services/api_service.dart';
import '../services/activity_context_service.dart';
import '../services/usage_stats_service.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key});

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  final _api = ApiService();
  final _activityService = ActivityContextService();
  final _usageService = UsageStatsService();

  // On-device screen time data (7-day map: date -> minutes)
  Map<String, double> _localUsageByDay = {};
  double _localTotalMinutes = 0;
  double _localAvgMinutes = 0;

  Map<String, dynamic>? _sleepSummary;
  Map<String, dynamic>? _insights;

  // Local activity context (no backend dependency)
  String _currentActivity = 'idle';
  bool _screenOn = false;

  bool _loading = true;
  bool _insightsLoading = false;
  bool _usagePermissionDenied = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    await Future.wait([
      _loadLocalUsage(),
      _loadSleep(),
      _loadLocalContext(),
    ]);
    setState(() => _loading = false);
  }

  /// Read screen time directly from the device (no backend needed)
  Future<void> _loadLocalUsage() async {
    try {
      final now = DateTime.now();
      final Map<String, double> byDay = {};
      double total = 0;

      for (int i = 6; i >= 0; i--) {
        final day = now.subtract(Duration(days: i));
        final start = DateTime(day.year, day.month, day.day);
        final end = i == 0 ? now : DateTime(day.year, day.month, day.day, 23, 59, 59);

        final label = '${_dayLabel(day.weekday)}'; // Mon, Tue…
        try {
          final infos = await AppUsage().getAppUsage(start, end);
          double minutes = 0;
          for (final info in infos) {
            final m = info.usage.inSeconds / 60.0;
            if (m < 0.5) continue; // skip negligible
            final lower = info.appName.toLowerCase();
            // Skip system noise
            if (['android', 'launcher', 'systemui', 'inputmethod', 'keyboard',
                 'setup', 'provision'].any((s) => lower.contains(s))) continue;
            minutes += m;
          }
          byDay[label] = minutes;
          total += minutes;
        } catch (_) {
          byDay[label] = 0;
        }
      }

      setState(() {
        _localUsageByDay = byDay;
        _localTotalMinutes = total;
        _localAvgMinutes = total / 7;
        _usagePermissionDenied = false;
      });

      // Also flush aggregated data to backend in the background
      try {
        final stats = await _usageService.getDailyStats();
        if ((stats['total_screen_minutes'] as int) > 0) {
          _usageService.logUsage(
            appName: 'total',
            durationSeconds: (stats['total_screen_minutes'] as int) * 60,
          );
          await _usageService.flush();
        }
      } catch (_) {}
    } catch (e) {
      // Permission denied or unavailable
      setState(() {
        _usagePermissionDenied = true;
        _localUsageByDay = {};
      });
    }
  }

  /// Read local context — no network call
  Future<void> _loadLocalContext() async {
    setState(() {
      _currentActivity = _activityService.currentActivity;
      _screenOn = true; // if this screen is open, screen is on
    });
  }

  Future<void> _loadSleep() async {
    try {
      _sleepSummary = await _api.getSleepSummary();
    } catch (_) {
      _sleepSummary = {};
    }
  }

  String _dayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Routine Insights', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _insightsLoading ? Icons.hourglass_top : Icons.auto_awesome,
              color: const Color(0xFFE8592B),
            ),
            onPressed: _insightsLoading ? null : _generateInsights,
            tooltip: 'Generate AI insights',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Current Activity Context (local — no backend)
                _contextCard(),
                const SizedBox(height: 16),

                // Screen Time from device
                _screenTimeSection(),
                const SizedBox(height: 16),

                // Sleep Summary
                _sleepSection(),
                const SizedBox(height: 16),

                // AI Insights
                if (_insights != null) _insightsCard(),
                const SizedBox(height: 80),
              ]),
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  CURRENT CONTEXT  (reads from local ActivityContextService)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _contextCard() {
    final activityIcons = {
      'studying': Icons.school,
      'browsing': Icons.language,
      'idle': Icons.phone_android,
      'gaming': Icons.sports_esports,
      'social_media': Icons.people,
      'messaging': Icons.chat_bubble,
    };

    final activityColors = {
      'studying': const Color(0xFF059669),
      'browsing': const Color(0xFF6366F1),
      'gaming': const Color(0xFFE8592B),
      'social_media': const Color(0xFF8B5CF6),
      'messaging': const Color(0xFF0EA5E9),
      'idle': const Color(0xFF6B7280),
    };

    final color = activityColors[_currentActivity] ?? const Color(0xFF6366F1);
    final label = _currentActivity == 'idle'
        ? 'Idle / Screen Off'
        : _currentActivity.replaceAll('_', ' ').toUpperCase();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(14)),
          child: Icon(activityIcons[_currentActivity] ?? Icons.phone_android,
              color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Current Activity', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          Text('Tracked on-device • updates as you use apps',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
        ])),
        if (_screenOn)
          const Icon(Icons.screen_lock_portrait, color: Colors.white70, size: 18),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SCREEN TIME (from device via app_usage)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _screenTimeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.phone_android, color: Color(0xFFE8592B), size: 20),
          SizedBox(width: 8),
          Text('Screen Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 4),
        Text('Last 7 days • live from your device',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 16),

        if (_usagePermissionDenied)
          _permissionBanner()
        else if (_localUsageByDay.isEmpty || _localUsageByDay.values.every((v) => v == 0))
          _noDataPlaceholder()
        else ...[
          SizedBox(
            height: 160,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (_localUsageByDay.values.reduce((a, b) => a > b ? a : b) * 1.25).clamp(10, double.infinity),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    '${rod.toY.toStringAsFixed(0)} min',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final days = _localUsageByDay.keys.toList();
                    if (value.toInt() < days.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(days[value.toInt()],
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                )),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barGroups: _localUsageByDay.entries.toList().asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [BarChartRodData(
                    toY: e.value.value,
                    width: 24,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)],
                      begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    ),
                  )],
                );
              }).toList(),
            )),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Total: ${_localTotalMinutes.toStringAsFixed(0)} min',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 16),
            Text('Avg: ${_localAvgMinutes.toStringAsFixed(0)} min/day',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ]),
        ],
      ]),
    );
  }

  Widget _permissionBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8592B).withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        const Icon(Icons.lock_outline, color: Color(0xFFE8592B), size: 28),
        const SizedBox(height: 8),
        const Text('Usage Access Required',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text('Grant "Usage Access" in Settings so CampusFlow can show your screen time.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () async {
            // AppUsage package requires the user to go to Settings manually
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Go to Settings → Apps → Special app access → Usage access → CampusFlow')),
            );
          },
          icon: const Icon(Icons.settings_outlined, size: 16),
          label: const Text('How to grant access'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE8592B),
            foregroundColor: Colors.white,
          ),
        ),
      ]),
    );
  }

  Widget _noDataPlaceholder() {
    return Container(
      height: 100,
      alignment: Alignment.center,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.hourglass_empty, size: 28, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text('No usage recorded yet today',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        Text('Data builds up as you use your phone',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SLEEP SUMMARY
  // ═══════════════════════════════════════════════════════════════════════

  Widget _sleepSection() {
    final s = _sleepSummary ?? {};
    final avgHours = s['avg_hours'] ?? '-';
    final entries = (s['daily'] as List?) ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bedtime_outlined, color: Color(0xFF6366F1), size: 20),
          const SizedBox(width: 8),
          const Text('Sleep Tracker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Avg: ${avgHours}h', style: const TextStyle(
              color: Color(0xFF6366F1), fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 16),

        if (entries.isNotEmpty)
          ...entries.take(5).map((entry) {
            final day = entry as Map<String, dynamic>;
            final hours = (day['hours'] as num?)?.toDouble() ?? 0;
            final quality = hours >= 7 ? 'Good' : hours >= 5 ? 'Fair' : 'Poor';
            final color = hours >= 7 ? const Color(0xFF059669) : hours >= 5 ? const Color(0xFFD97706) : Colors.red;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 60, child: Text(
                  day['date']?.toString().substring(5) ?? '',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                )),
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (hours / 10).clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 8,
                  ),
                )),
                const SizedBox(width: 10),
                SizedBox(width: 50, child: Text('${hours.toStringAsFixed(1)}h',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(quality, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                ),
              ]),
            );
          })
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text('No sleep data yet',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13))),
          ),

        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showSleepLogSheet,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add, color: Color(0xFF6366F1), size: 16),
              SizedBox(width: 6),
              Text('Log last night\'s sleep', style: TextStyle(color: Color(0xFF6366F1), fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  AI INSIGHTS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _insightsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8592B).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8592B).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, color: Color(0xFFE8592B), size: 20),
          SizedBox(width: 8),
          Text('AI Routine Insights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 12),
        Text(_insights!['insights'] ?? _insights!['analysis'] ?? 'No insights generated yet',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.6)),

        if ((_insights!['recommendations'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          const Text('Recommendations:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          ...((_insights!['recommendations'] as List).take(3).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline, color: Color(0xFFE8592B), size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(r.toString(), style: const TextStyle(fontSize: 13))),
            ]),
          ))),
        ],
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _generateInsights() async {
    setState(() => _insightsLoading = true);
    try {
      final result = await _api.generateRoutineInsights();
      setState(() { _insights = result; _insightsLoading = false; });
    } catch (e) {
      setState(() => _insightsLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showSleepLogSheet() {
    TimeOfDay bedTime = const TimeOfDay(hour: 23, minute: 0);
    TimeOfDay wakeTime = const TimeOfDay(hour: 7, minute: 0);

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheetState) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Log Sleep', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: bedTime);
                  if (t != null) setSheetState(() => bedTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    const Icon(Icons.bedtime, color: Color(0xFF6366F1)),
                    const SizedBox(height: 4),
                    const Text('Bedtime', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(bedTime.format(ctx), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ),
              )),
              const SizedBox(width: 12),
              Expanded(child: GestureDetector(
                onTap: () async {
                  final t = await showTimePicker(context: ctx, initialTime: wakeTime);
                  if (t != null) setSheetState(() => wakeTime = t);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    const Icon(Icons.wb_sunny, color: Color(0xFFD97706)),
                    const SizedBox(height: 4),
                    const Text('Wake Up', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text(wakeTime.format(ctx), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ),
              )),
            ]),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () async {
                final bedStr = '${bedTime.hour.toString().padLeft(2, '0')}:${bedTime.minute.toString().padLeft(2, '0')}';
                final wakeStr = '${wakeTime.hour.toString().padLeft(2, '0')}:${wakeTime.minute.toString().padLeft(2, '0')}';
                final today = DateTime.now().toIso8601String().substring(0, 10);
                await _api.logSleepEvent(bedStr, wakeStr, today);
                if (ctx.mounted) { Navigator.pop(ctx); _loadData(); }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep logged! 😴'), backgroundColor: Color(0xFF059669)));
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white,
                padding: const EdgeInsets.all(14)),
              child: const Text('Save Sleep Log'),
            )),
          ]),
        );
      }),
    );
  }
}
