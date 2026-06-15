import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key});

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  final _api = ApiService();

  Map<String, dynamic>? _heatmap;
  Map<String, dynamic>? _sleepSummary;
  Map<String, dynamic>? _insights;
  Map<String, dynamic>? _currentContext;
  bool _loading = true;
  bool _insightsLoading = false;

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getUsageHeatmap(),
        _api.getSleepSummary(),
        _api.getCurrentContext(),
      ]);
      setState(() {
        _heatmap = results[0];
        _sleepSummary = results[1];
        _currentContext = results[2];
        _loading = false;
      });
    } catch (e) { setState(() => _loading = false); }
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
                // Current Activity Context
                if (_currentContext != null) _contextCard(),
                const SizedBox(height: 16),

                // Screen Time Heatmap
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
  //  CURRENT CONTEXT
  // ═══════════════════════════════════════════════════════════════════════

  Widget _contextCard() {
    final ctx = _currentContext!;
    final activity = ctx['context'] ?? 'Unknown';
    final activityIcons = {
      'studying': Icons.school, 'browsing': Icons.language,
      'idle': Icons.phone_android, 'gaming': Icons.sports_esports,
      'social_media': Icons.people, 'messaging': Icons.chat_bubble,
    };

    final screenOn = ctx['screen_on'] == true;
    final headphones = ctx['headphones_connected'] == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
          child: Icon(activityIcons[activity] ?? Icons.phone_android, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Current Context', style: TextStyle(color: Colors.white70, fontSize: 12)),
          Text(activity.toString().replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          if (ctx['last_updated'] != null)
            Text('Last active: ${_formatTime(ctx['last_updated'])}', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
        ])),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (screenOn) const Icon(Icons.screen_lock_portrait, color: Colors.white, size: 16),
            if (headphones) const Icon(Icons.headphones, color: Colors.white, size: 16),
          ],
        )
      ]),
    );
  }

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoTime;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  SCREEN TIME HEATMAP
  // ═══════════════════════════════════════════════════════════════════════

  Widget _screenTimeSection() {
    final heatData = _heatmap?['heatmap'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.phone_android, color: Color(0xFFE8592B), size: 20),
          SizedBox(width: 8),
          Text('Screen Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        const SizedBox(height: 6),
        Text('Last 7 days',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(height: 16),

        if (heatData.isNotEmpty) ...[
          // Bar chart
          SizedBox(
            height: 160,
            child: BarChart(BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: _getMaxUsage(heatData) * 1.2,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${rod.toY.toStringAsFixed(0)} min',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final days = heatData.keys.toList();
                    if (value.toInt() < days.length) {
                      final day = days[value.toInt()];
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          day.length >= 3 ? day.substring(0, 3) : day,
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                )),
              ),
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: false),
              barGroups: heatData.entries.toList().asMap().entries.map((entry) {
                final value = (entry.value.value as num?)?.toDouble() ?? 0;
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [BarChartRodData(
                    toY: value,
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
          // Total
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Total: ${_heatmap?['total_minutes'] ?? 0} min',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 16),
            Text('Avg: ${_heatmap?['avg_daily_minutes'] ?? 0} min/day',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ]),
        ] else ...[
          Container(
            height: 120,
            alignment: Alignment.center,
            child: Text('No usage data yet', style: TextStyle(color: Colors.grey.shade400)),
          ),
        ],
      ]),
    );
  }

  double _getMaxUsage(Map<String, dynamic> data) {
    double max = 0;
    for (final v in data.values) {
      final val = (v as num?)?.toDouble() ?? 0;
      if (val > max) max = val;
    }
    return max == 0 ? 100 : max;
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
        // Manual sleep log
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
          ...(((_insights!['recommendations'] as List).take(3).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline, color: Color(0xFFE8592B), size: 14),
              const SizedBox(width: 6),
              Expanded(child: Text(r.toString(), style: const TextStyle(fontSize: 13))),
            ]),
          )))),
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
