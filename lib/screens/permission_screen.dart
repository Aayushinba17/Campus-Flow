import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const PermissionScreen({super.key, required this.onComplete});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  final Map<String, _PermissionItem> _permissions = {
    'notifications': _PermissionItem(
      title: 'Notifications',
      subtitle: 'Read & classify your app notifications',
      icon: Icons.notifications_outlined,
      color: const Color(0xFFE8592B),
      permission: Permission.notification,
      status: PermissionStatus.denied,
    ),
    'microphone': _PermissionItem(
      title: 'Microphone',
      subtitle: 'For voice-to-task conversion',
      icon: Icons.mic_outlined,
      color: const Color(0xFF6366F1),
      permission: Permission.microphone,
      status: PermissionStatus.denied,
    ),
    'camera': _PermissionItem(
      title: 'Camera',
      subtitle: 'Scan timetable photos',
      icon: Icons.camera_alt_outlined,
      color: const Color(0xFF059669),
      permission: Permission.camera,
      status: PermissionStatus.denied,
    ),
    'storage': _PermissionItem(
      title: 'Storage',
      subtitle: 'Save & access note files',
      icon: Icons.folder_outlined,
      color: const Color(0xFFD97706),
      permission: Permission.storage,
      status: PermissionStatus.denied,
    ),
    'location': _PermissionItem(
      title: 'Location',
      subtitle: 'Campus zone detection for smart reminders',
      icon: Icons.location_on_outlined,
      color: const Color(0xFF2563EB),
      permission: Permission.location,
      status: PermissionStatus.denied,
    ),
  };

  @override
  void initState() { super.initState(); _checkStatuses(); }

  Future<void> _checkStatuses() async {
    for (final entry in _permissions.entries) {
      final status = await entry.value.permission.status;
      setState(() => entry.value.status = status);
    }
  }

  int get _grantedCount => _permissions.values.where((p) => p.status.isGranted).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Permissions', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('CampusFlow needs a few permissions to work its magic',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
              const SizedBox(height: 8),

              // Progress
              Row(children: [
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _grantedCount / _permissions.length,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFE8592B)),
                    minHeight: 6,
                  ),
                )),
                const SizedBox(width: 10),
                Text('$_grantedCount/${_permissions.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
              const SizedBox(height: 24),

              Expanded(
                child: ListView(children: _permissions.entries.map((entry) {
                  final p = entry.value;
                  final isGranted = p.status.isGranted;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      onTap: isGranted ? null : () => _requestPermission(entry.key, p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isGranted
                              ? p.color.withOpacity(0.1)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isGranted ? p.color.withOpacity(0.4) : Colors.white12,
                            width: isGranted ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: p.color.withOpacity(isGranted ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(p.icon, color: p.color, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.title, style: TextStyle(
                              color: isGranted ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(p.subtitle, style: TextStyle(
                              color: Colors.white.withOpacity(0.4), fontSize: 12)),
                          ])),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: isGranted
                                ? Icon(Icons.check_circle, color: p.color, key: const ValueKey('granted'))
                                : Container(
                                    key: const ValueKey('grant'),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: p.color.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text('Grant', style: TextStyle(
                                      color: p.color, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ),
                          ),
                        ]),
                      ),
                    ),
                  );
                }).toList()),
              ),

              // Continue button
              GestureDetector(
                onTap: widget.onComplete,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFE8592B), Color(0xFFFF8C5A)]),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFE8592B).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: const Center(child: Text('Continue',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                ),
              ),
              const SizedBox(height: 8),
              Center(child: Text('You can change these in Settings anytime',
                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestPermission(String key, _PermissionItem item) async {
    final status = await item.permission.request();
    setState(() => item.status = status);

    if (status.isPermanentlyDenied && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.title} permanently denied. Open settings to enable.'),
          action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
        ),
      );
    }
  }
}

class _PermissionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Permission permission;
  PermissionStatus status;

  _PermissionItem({
    required this.title, required this.subtitle, required this.icon,
    required this.color, required this.permission, required this.status,
  });
}
