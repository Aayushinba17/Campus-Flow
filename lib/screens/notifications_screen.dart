import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabController;

  List<dynamic> _notifications = [];
  List<dynamic> _deadlines = [];
  List<dynamic> _missedCalls = [];
  Map<String, dynamic>? _digest;
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getRecentNotifications(),
        _api.getExtractedDeadlines(),
        _api.getMissedCalls(),
        _api.getNotificationStats(),
      ]);
      setState(() {
        _notifications = results[0] as List;
        _deadlines = results[1] as List;
        _missedCalls = results[2] as List;
        _stats = results[3] as Map<String, dynamic>;
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
        title: const Text('Updates', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Color(0xFFE8592B)),
            onPressed: _generateDigest,
            tooltip: 'AI Digest',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE8592B),
          labelColor: const Color(0xFFE8592B),
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.notifications_outlined, size: 16), const SizedBox(width: 4),
              const Text('All'),
              if (_notifications.isNotEmpty) _badge(_notifications.length),
            ])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.flag_outlined, size: 16), const SizedBox(width: 4),
              const Text('Deadlines'),
              if (_deadlines.isNotEmpty) _badge(_deadlines.length),
            ])),
            const Tab(text: 'Missed Calls'),
            const Tab(text: 'Email/Slack'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _allNotificationsTab(),
          _deadlinesTab(),
          _missedCallsTab(),
          _emailTab(),
        ],
      ),
    );
  }

  Widget _badge(int count) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: const Color(0xFFE8592B), borderRadius: BorderRadius.circular(10)),
    child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
  );

  // ═══════════════════════════════════════════════════════════════════════
  //  ALL NOTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _allNotificationsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              // AI Digest card (if generated)
              if (_digest != null) _digestCard(),

              // Stats bar
              if (_stats != null) _statsBar(),
              const SizedBox(height: 12),

              // Add notification manually button
              GestureDetector(
                onTap: _showAddNotificationSheet,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8592B).withValues(alpha: 0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.add_circle_outline, color: Color(0xFFE8592B), size: 22),
                    SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Add Update / Message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFFE8592B))),
                      Text('Paste a WhatsApp / SMS message to extract deadlines', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ])),
                    Icon(Icons.chevron_right, color: Color(0xFFE8592B)),
                  ]),
                ),
              ),

              // Notification list
              if (_notifications.isEmpty)
                _emptyState('No notifications yet', 'Add messages above to extract deadlines, or grant notification access in Settings')
              else
                ...(_notifications.map((n) => _notificationTile(n as Map<String, dynamic>))),
            ]),
    );
  }

  void _showAddNotificationSheet() {
    final bodyCtrl = TextEditingController();
    final senderCtrl = TextEditingController();
    String selectedApp = 'WhatsApp';
    final apps = ['WhatsApp', 'Telegram', 'SMS', 'Gmail', 'Other'];

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
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Add Message / Update', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Paste a message — AI will extract deadlines & tasks', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              TextField(
                controller: senderCtrl,
                decoration: const InputDecoration(labelText: 'Sender (e.g. Prof. Sharma)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bodyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Paste message here...', border: OutlineInputBorder(), alignLabelWithHint: true),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedApp,
                decoration: const InputDecoration(labelText: 'Source app', border: OutlineInputBorder()),
                items: apps.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                onChanged: (v) => setSheetState(() => selectedApp = v!),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () async {
                  if (bodyCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx);
                  showDialog(context: context, barrierDismissible: false,
                    builder: (_) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      content: const Row(children: [
                        CircularProgressIndicator(color: Color(0xFFE8592B)),
                        SizedBox(width: 16), Text('AI extracting info...'),
                      ]),
                    ),
                  );
                  try {
                    // Derive package name & display name from the selected app
                    const appPackages = {
                      'WhatsApp':  'com.whatsapp',
                      'Telegram':  'org.telegram.messenger',
                      'SMS':       'com.android.mms',
                      'Gmail':     'com.google.android.gm',
                      'Other':     'com.unknown.app',
                    };
                    final bodyText = bodyCtrl.text.trim();
                    // Use first ~60 chars of the message as the notification title
                    final titleText = bodyText.length > 60
                        ? '${bodyText.substring(0, 60)}…'
                        : bodyText;

                    await _api.ingestNotifications([{
                      'source_app':  selectedApp,
                      'app_package': appPackages[selectedApp] ?? 'com.unknown.app',
                      'app_name':    selectedApp,
                      'title':       titleText,
                      'sender':      senderCtrl.text.isNotEmpty ? senderCtrl.text : 'Unknown',
                      'body':        bodyText,
                      'timestamp':   DateTime.now().toIso8601String(),
                    }]);
                    if (mounted) Navigator.pop(context);
                    _loadAll();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message added & analyzed!'), backgroundColor: Color(0xFF059669)),
                      );
                    }
                  } catch (e) {
                    if (mounted) Navigator.pop(context);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8592B), foregroundColor: Colors.white, padding: const EdgeInsets.all(14)),
                child: const Text('Add & Extract'),
              )),
            ]),
          ),
        );
      }),
    );
  }


  Widget _digestCard() {
    final d = _digest!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, color: Colors.white70, size: 16),
          SizedBox(width: 6),
          Text('AI Morning Briefing', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 10),
        Text(d['greeting'] ?? 'Here\'s your update:',
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        if ((d['urgent_items'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          ...((d['urgent_items'] as List).take(4).map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Icon(Icons.circle, color: Colors.white70, size: 6),
              const SizedBox(width: 8),
              Expanded(child: Text(item.toString(), style: const TextStyle(color: Colors.white, fontSize: 13))),
            ]),
          ))),
        ],
      ]),
    );
  }

  Widget _statsBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _statItem('Total', _stats?['total']?.toString() ?? '0', Icons.notifications),
        _statItem('Urgent', _stats?['urgent']?.toString() ?? '0', Icons.priority_high),
        _statItem('Academic', _stats?['academic']?.toString() ?? '0', Icons.school),
      ]),
    );
  }

  Widget _statItem(String label, String value, IconData icon) => Column(children: [
    Icon(icon, color: const Color(0xFFE8592B), size: 20),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
    Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
  ]);

  Widget _notificationTile(Map<String, dynamic> n) {
    final app = n['source_app'] ?? 'Unknown';
    final priority = n['priority'] ?? 2;
    final colors = {1: Colors.grey, 2: Colors.blue, 3: const Color(0xFFE8592B), 4: Colors.red, 5: Colors.red};
    final appIcons = {
      'WhatsApp': Icons.chat_bubble,
      'Telegram': Icons.send,
      'Gmail': Icons.email,
      'SMS': Icons.sms,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: priority >= 4 ? Border.all(color: Colors.red.withValues(alpha: 0.3)) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: (colors[priority] ?? Colors.grey).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(appIcons[app] ?? Icons.notifications, color: colors[priority], size: 20),
        ),
        title: Text(n['title'] ?? n['sender'] ?? app,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(n['body'] ?? n['text'] ?? '',
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: Text(_timeAgo(n['timestamp'] ?? ''),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  DEADLINES TAB
  // ═══════════════════════════════════════════════════════════════════════

  Widget _deadlinesTab() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)));
    if (_deadlines.isEmpty) return _emptyState('No deadlines detected', 'Claude extracts deadlines from your messages automatically');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deadlines.length,
      itemBuilder: (_, i) {
        final d = _deadlines[i] as Map<String, dynamic>;
        final isToday = d['deadline'] == DateFormat('yyyy-MM-dd').format(DateTime.now());
        final isTomorrow = d['deadline'] == DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 1)));

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: isToday ? Border.all(color: Colors.red.withValues(alpha: 0.4), width: 2) : null,
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isToday ? Colors.red.withValues(alpha: 0.1)
                    : isTomorrow ? Colors.orange.withValues(alpha: 0.1)
                    : const Color(0xFFE8592B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.flag, size: 20,
                color: isToday ? Colors.red : isTomorrow ? Colors.orange : const Color(0xFFE8592B)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text('Due: ${d['deadline'] ?? 'Unknown'} • via ${d['source_app'] ?? 'message'}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
            if (isToday)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text('TODAY', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
              )
            else if (isTomorrow)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text('TOMORROW', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ]),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  MISSED CALLS TAB
  // ═══════════════════════════════════════════════════════════════════════

  Widget _missedCallsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFFE8592B)));
    if (_missedCalls.isEmpty) return _emptyState('No missed calls logged', 'Missed call context will appear here');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _missedCalls.length,
      itemBuilder: (_, i) {
        final call = _missedCalls[i] as Map<String, dynamic>;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.phone_missed, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(call['caller_name'] ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                Text(call['missed_at'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
            ]),
            if (call['context_summary'] != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8592B).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFE8592B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(call['context_summary'],
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A2E)))),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  EMAIL/SLACK TAB
  // ═══════════════════════════════════════════════════════════════════════

  Widget _emailTab() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      // Summarize button
      GestureDetector(
        onTap: _summarizeEmails,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(children: [
            Icon(Icons.email_outlined, color: Colors.white),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Summarize Recent Emails', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              Text('AI reads notification emails & creates a 2-line summary', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            Icon(Icons.chevron_right, color: Colors.white70),
          ]),
        ),
      ),
      const SizedBox(height: 20),

      // Action items
      const Text('Action Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      FutureBuilder<List<dynamic>>(
        future: _api.getEmailActionItems(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFE8592B))));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return _emptyState('No action items', 'Email action items requiring reply will appear here');
          }
          return Column(children: items.map((item) {
            final a = item as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.reply, color: Color(0xFF6366F1), size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['action'] ?? a['title'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(a['from'] ?? a['source'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ])),
              ]),
            );
          }).toList());
        },
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _generateDigest() async {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Row(children: [
          CircularProgressIndicator(color: Color(0xFFE8592B)),
          SizedBox(width: 16), Text('Generating AI digest...'),
        ]),
      ),
    );
    try {
      final result = await _api.getMorningDigest();
      if (mounted) Navigator.pop(context);
      setState(() => _digest = result['digest'] as Map<String, dynamic>?);
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _summarizeEmails() async {
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: const Row(children: [
          CircularProgressIndicator(color: Color(0xFF6366F1)),
          SizedBox(width: 16), Text('AI summarizing...'),
        ]),
      ),
    );
    try {
      final result = await _api.summarizeFromNotifications();
      if (mounted) Navigator.pop(context);
      if (mounted) _showSummarySheet(result);
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _showSummarySheet(Map<String, dynamic> result) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text('Email Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
          const SizedBox(height: 16),
          Text(result['summary'] ?? 'No summary generated',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.6)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _emptyState(String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            await NotificationListenerService.requestPermission();
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8592B), foregroundColor: Colors.white),
          child: const Text('Grant Access'),
        ),
      ]),
    ),
  );

  String _timeAgo(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(timestamp);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) { return ''; }
  }
}