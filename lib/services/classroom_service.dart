import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../services/user_service.dart';

/// Handles Google Classroom connection and the autonomous activity feed.
/// Add `url_launcher: ^6.3.0` to pubspec.yaml.
class ClassroomService {
  static final ClassroomService _instance = ClassroomService._internal();
  factory ClassroomService() => _instance;
  ClassroomService._internal();

  final String _base = AppConstants.baseUrl;

  // ── 1. Connection status ────────────────────────────────────────────

  Future<bool> isConnected() async {
    try {
      final r = await http.get(Uri.parse('${AppConstants.baseUrl}/api/classroom/status/${await UserService.getUserId()}'));
      final data = jsonDecode(r.body);
      return data['connected'] == true;
    } catch (_) { return false; }
  }

  // ── 2. Start OAuth — opens system browser ───────────────────────────

  /// Opens Google's consent screen in the device browser. After the user
  /// approves, Google redirects to the backend's /oauth/callback, which
  /// shows a small "connected" page and auto-closes.
  ///
  /// Call `isConnected()` again ~3-5 seconds after this, or when the app
  /// resumes (AppLifecycleState.resumed), to detect completion.
  Future<void> startConnection() async {
    final r = await http.get(Uri.parse('$_base/api/classroom/oauth/start?user_id=${await UserService.getUserId()}'));
    final data = jsonDecode(r.body);
    final authUrl = data['auth_url'] as String?;
    if (authUrl == null) return;

    final uri = Uri.parse(authUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── 3. Sync — pulls assignments, writes directly ────────────────────

  Future<Map<String, dynamic>> sync() async {
    final r = await http.post(
      Uri.parse('$_base/api/classroom/sync'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': (await UserService.getUserId())}),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncAnnouncements() async {
    final r = await http.post(
      Uri.parse('$_base/api/classroom/sync-announcements'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': (await UserService.getUserId())}),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> disconnect() async {
    await http.delete(Uri.parse('$_base/api/classroom/disconnect/${await UserService.getUserId()}'));
  }

  // ── 4. Activity feed (autonomous actions log) ───────────────────────

  Future<List<Map<String, dynamic>>> getActivityFeed({
    int limit = 20,
    bool unreadOnly = false,
  }) async {
    final r = await http.get(Uri.parse(
      '$_base/api/notifications/activity-feed/${await UserService.getUserId()}?limit=$limit&unread_only=$unreadOnly',
    ));
    final data = jsonDecode(r.body);
    return (data['activity'] as List? ?? []).cast<Map<String, dynamic>>();
  }

  Future<bool> undoActivity(String logId) async {
    final r = await http.post(
      Uri.parse('$_base/api/notifications/activity-feed/${await UserService.getUserId()}/undo/$logId'),
    );
    if (r.statusCode != 200) return false;
    final data = jsonDecode(r.body);
    return data['undone'] == true;
  }
}


// ═══════════════════════════════════════════════════════════════════════
// Example widget: Settings screen entry + Activity feed screen
// ═══════════════════════════════════════════════════════════════════════

class ClassroomConnectTile extends StatefulWidget {
  const ClassroomConnectTile({super.key});

  @override
  State<ClassroomConnectTile> createState() => _ClassroomConnectTileState();
}

class _ClassroomConnectTileState extends State<ClassroomConnectTile>
    with WidgetsBindingObserver {
  final _classroom = ClassroomService();
  bool _connected = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the user returns from the OAuth browser, re-check status
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final connected = await _classroom.isConnected();
    if (mounted) setState(() => _connected = connected);
    if (connected) _runSync();
  }

  Future<void> _runSync() async {
    setState(() => _syncing = true);
    final result = await _classroom.sync();
    if (mounted) {
      setState(() => _syncing = false);
      final created = result['tasks_created'] as List? ?? [];
      if (created.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${created.length} new assignment(s) added automatically'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.school_outlined, color: Color(0xFFE8592B)),
      title: const Text('Google Classroom'),
      subtitle: Text(_connected
        ? (_syncing ? 'Syncing assignments...' : 'Connected — auto-syncing assignments')
        : 'Connect to auto-add assignments and deadlines'),
      trailing: _connected
        ? IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _runSync,
          )
        : ElevatedButton(
            onPressed: () => _classroom.startConnection(),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8592B)),
            child: const Text('Connect', style: TextStyle(color: Colors.white)),
          ),
    );
  }
}


class ActivityFeedScreen extends StatefulWidget {
  const ActivityFeedScreen({super.key});

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen> {
  final _classroom = ClassroomService();
  List<Map<String, dynamic>> _activity = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activity = await _classroom.getActivityFeed();
    setState(() { _activity = activity; _loading = false; });
  }

  Future<void> _undo(Map<String, dynamic> entry) async {
    final ok = await _classroom.undoActivity(entry['log_id'] as String);
    if (ok) {
      if (!mounted) return;
      setState(() => entry['undone'] = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Undone')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent activity')),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _activity.isEmpty
          ? const Center(child: Text('Nothing yet — I\'ll log what I do here'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _activity.length,
              itemBuilder: (context, i) {
                final entry = _activity[i];
                final undone = entry['undone'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      entry['action'] == 'task_added' ? Icons.task_alt_outlined
                        : entry['action'] == 'event_added' ? Icons.event_outlined
                        : Icons.lightbulb_outline,
                      color: undone ? Colors.grey : const Color(0xFFE8592B),
                    ),
                    title: Text(
                      entry['detail'] as String? ?? '',
                      style: TextStyle(
                        decoration: undone ? TextDecoration.lineThrough : null,
                        color: undone ? Colors.grey : null,
                      ),
                    ),
                    trailing: (entry['undoable'] == true && !undone)
                      ? TextButton(
                          onPressed: () => _undo(entry),
                          child: const Text('Undo'),
                        )
                      : null,
                  ),
                );
              },
            ),
    );
  }
}