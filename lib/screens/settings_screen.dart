import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../services/user_prefs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  bool _classroomConnected = false;
  bool _checking = true;
  String? _userId;
  String? _userName;
  int _zoneRadius = 150;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final id = await UserService.getUserId();
    final name = await UserService.getUserName();
    final radius = await UserPrefs.getZoneRadius();
    try {
      final connected = await _api.isClassroomConnected();
      setState(() {
        _userId = id;
        _userName = name;
        _zoneRadius = radius;
        _classroomConnected = connected;
        _checking = false;
      });
    } catch (_) {
      setState(() {
        _userId = id;
        _userName = name;
        _zoneRadius = radius;
        _checking = false;
      });
    }
  }

  Future<void> _connectClassroom() async {
    try {
      final authUrl = await _api.getClassroomAuthUrl();
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        // Poll status every 3s for 60s to detect connection
        for (var i = 0; i < 20; i++) {
          await Future.delayed(const Duration(seconds: 3));
          final connected = await _api.isClassroomConnected();
          if (connected) {
            if (!mounted) return;
            setState(() => _classroomConnected = true);
            // Trigger first sync
            await _api.syncClassroom();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Classroom connected and synced')),
            );
            return;
          }
        }
      } else {
        throw 'Cannot open browser';
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

  Future<void> _disconnectClassroom() async {
    await _api.disconnectClassroom();
    setState(() => _classroomConnected = false);
  }

  Future<void> _resetZoneAtCurrentLocation(String zoneName) async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
      return;
    }
    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    await _api.updateZoneTransition(zoneName, 'reset',
        lat: pos.latitude, lng: pos.longitude);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$zoneName updated to your current location')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Name'),
                  subtitle: Text(_userName ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final controller = TextEditingController(text: _userName);
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Your name'),
                          content: TextField(controller: controller),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(context, controller.text),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                      if (newName != null && newName.trim().isNotEmpty) {
                        await UserService.setUserName(newName);
                        setState(() => _userName = newName.trim());
                      }
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.fingerprint),
                  title: const Text('User ID'),
                  subtitle: Text(_userId ?? ''),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.school, color: Color(0xFF34A853)),
                  title: const Text('Google Classroom'),
                  subtitle: Text(_classroomConnected ? 'Connected — assignments syncing' : 'Not connected'),
                  trailing: _classroomConnected
                      ? TextButton(onPressed: _disconnectClassroom, child: const Text('Disconnect'))
                      : ElevatedButton(onPressed: _connectClassroom, child: const Text('Connect')),
                ),
                if (_classroomConnected)
                  ListTile(
                    leading: const Icon(Icons.sync),
                    title: const Text('Sync now'),
                    onTap: () async {
                      final result = await _api.syncClassroom();
                      final created = (result['tasks_created'] as List?)?.length ?? 0;
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Synced. $created new assignments.')),
                      );
                    },
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Update "Home" location'),
                  subtitle: const Text('Tap when you\'re at home'),
                  onTap: () => _resetZoneAtCurrentLocation('home'),
                ),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Update "Campus" location'),
                  subtitle: const Text('Tap when you\'re on campus'),
                  onTap: () => _resetZoneAtCurrentLocation('campus'),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text('Zone Radius', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Slider(
                  value: _zoneRadius.toDouble(),
                  min: 50,
                  max: 500,
                  divisions: 9,
                  label: '${_zoneRadius}m',
                  onChanged: (val) {
                    setState(() => _zoneRadius = val.toInt());
                  },
                  onChangeEnd: (val) {
                    UserPrefs.setZoneRadius(val.toInt());
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Current: ${_zoneRadius}m (affects home/campus detection)', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}