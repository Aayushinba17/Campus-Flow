import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../services/api_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _api = ApiService();
  int _currentPage = 0;
  bool _uploading = false;
  String _uploadStatus = '';

  // Location zone data
  final _nameController = TextEditingController(text: 'Student');
  final List<Map<String, dynamic>> _zones = [];
  final _zoneTypes = [
    {'name': 'home', 'icon': Icons.home_outlined, 'label': 'Home / PG', 'color': Color(0xFF4CAF50)},
    {'name': 'campus', 'icon': Icons.school_outlined, 'label': 'Main Campus', 'color': Color(0xFFE8592B)},
    {'name': 'library', 'icon': Icons.local_library_outlined, 'label': 'Library', 'color': Color(0xFF2196F3)},
    {'name': 'hostel', 'icon': Icons.apartment_outlined, 'label': 'Hostel', 'color': Color(0xFF9C27B0)},
  ];

  final _pages = [
    {
      'title': 'Welcome to\nCampusFlow',
      'subtitle': 'Your AI-powered campus life assistant',
      'icon': Icons.auto_awesome,
      'gradient': [Color(0xFFE8592B), Color(0xFFFF8C5A)],
    },
    {
      'title': 'Upload Your\nTimetable',
      'subtitle': 'Take a photo of your class schedule — AI extracts everything',
      'icon': Icons.calendar_today_outlined,
      'gradient': [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    },
    {
      'title': 'Mark Your\nLocations',
      'subtitle': 'So we can adjust reminders based on where you are',
      'icon': Icons.location_on_outlined,
      'gradient': [Color(0xFF059669), Color(0xFF34D399)],
    },
    {
      'title': 'You\'re All Set!',
      'subtitle': 'CampusFlow will now manage your student life intelligently',
      'icon': Icons.rocket_launch_outlined,
      'gradient': [Color(0xFFE8592B), Color(0xFFFF6B6B)],
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: Stack(
        children: [
          // Animated background
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  (_pages[_currentPage]['gradient'] as List<Color>)[0].withOpacity(0.15),
                  const Color(0xFF0F0F1A),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Skip button
                if (_currentPage < _pages.length - 1)
                  Align(
                    alignment: Alignment.topRight,
                    child: TextButton(
                      onPressed: _finishOnboarding,
                      child: const Text('Skip', style: TextStyle(color: Colors.white54)),
                    ),
                  ),

                // Page content
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemCount: _pages.length,
                    itemBuilder: (context, i) {
                      if (i == 1) return _timetableUploadPage();
                      if (i == 2) return _locationSetupPage();
                      return _introPage(i);
                    },
                  ),
                ),

                // Page indicators + Next button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                  child: Row(
                    children: [
                      // Dots
                      Row(
                        children: List.generate(_pages.length, (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          width: _currentPage == i ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == i
                                ? (_pages[_currentPage]['gradient'] as List<Color>)[0]
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        )),
                      ),
                      const Spacer(),
                      // Next / Get Started button
                      GestureDetector(
                        onTap: () {
                          if (_currentPage == _pages.length - 1) {
                            _finishOnboarding();
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: EdgeInsets.symmetric(
                            horizontal: _currentPage == _pages.length - 1 ? 32 : 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _pages[_currentPage]['gradient'] as List<Color>,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: (_pages[_currentPage]['gradient'] as List<Color>)[0].withOpacity(0.4),
                                blurRadius: 20, offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentPage == _pages.length - 1 ? 'Get Started' : 'Next',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _introPage(int index) {
    final page = _pages[index];
    final colors = page['gradient'] as List<Color>;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Glowing icon
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: colors[0].withOpacity(0.4), blurRadius: 40)],
            ),
            child: Icon(page['icon'] as IconData, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 48),
          Text(page['title'] as String,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.2)),
          const SizedBox(height: 16),
          Text(page['subtitle'] as String,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16, height: 1.5)),
          if (index == 0) ...[
            const SizedBox(height: 40),
            // Name input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Enter your name',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.person_outline, color: Colors.white.withOpacity(0.4)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timetableUploadPage() {
    final colors = _pages[1]['gradient'] as List<Color>;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: colors[0].withOpacity(0.4), blurRadius: 40)],
            ),
            child: const Icon(Icons.calendar_today_outlined, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 32),
          const Text('Upload Your Timetable',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('AI will extract your classes, rooms & professors',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
          const SizedBox(height: 40),

          // Upload buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _uploadOption(Icons.camera_alt_outlined, 'Camera', () => _pickImage(ImageSource.camera), colors),
              const SizedBox(width: 16),
              _uploadOption(Icons.photo_library_outlined, 'Gallery', () => _pickImage(ImageSource.gallery), colors),
            ],
          ),
          const SizedBox(height: 24),
          if (_uploading)
            Column(children: [
              CircularProgressIndicator(color: colors[0]),
              const SizedBox(height: 12),
              Text(_uploadStatus, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
            ])
          else if (_uploadStatus.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_uploadStatus,
                  style: const TextStyle(color: Colors.green, fontSize: 13))),
              ]),
            ),
          const SizedBox(height: 16),
          Text('You can also add classes manually later',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _uploadOption(IconData icon, String label, VoidCallback onTap, List<Color> colors) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130, height: 130,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50, height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors.map((c) => c.withOpacity(0.2)).toList()),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colors[0], size: 24),
            ),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _locationSetupPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Mark Your Locations',
            style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Tap zones you visit regularly — reminders adjust automatically',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
          const SizedBox(height: 32),
          ...(_zoneTypes.map((zone) {
            final isAdded = _zones.any((z) => z['zone_name'] == zone['name']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (isAdded) {
                      _zones.removeWhere((z) => z['zone_name'] == zone['name']);
                    } else {
                      _zones.add({
                        'zone_name': zone['name'],
                        'label': zone['label'],
                        'latitude': 28.6139, // Default Delhi coords — user updates via app
                        'longitude': 77.2090,
                        'radius_meters': 200,
                      });
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isAdded
                        ? (zone['color'] as Color).withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isAdded ? (zone['color'] as Color).withOpacity(0.5) : Colors.white12,
                      width: isAdded ? 2 : 1,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: (zone['color'] as Color).withOpacity(isAdded ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(zone['icon'] as IconData, color: zone['color'] as Color, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(zone['label'] as String,
                        style: TextStyle(
                          color: isAdded ? Colors.white : Colors.white60,
                          fontSize: 16, fontWeight: isAdded ? FontWeight.w600 : FontWeight.normal,
                        )),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isAdded
                          ? Icon(Icons.check_circle, color: zone['color'] as Color, key: const ValueKey('check'))
                          : const Icon(Icons.add_circle_outline, color: Colors.white30, key: ValueKey('add')),
                    ),
                  ]),
                ),
              ),
            );
          })),
          const SizedBox(height: 8),
          Text('${_zones.length} zone${_zones.length != 1 ? 's' : ''} selected',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    setState(() { _uploading = true; _uploadStatus = 'Uploading & extracting...'; });

    try {
      final result = await _api.uploadTimetableImage(File(picked.path));
      final count = result['classes_extracted'] ?? result['items'] ?? 0;
      setState(() { _uploading = false; _uploadStatus = '✅ $count classes extracted!'; });
    } catch (e) {
      setState(() { _uploading = false; _uploadStatus = 'Upload failed. You can try again later.'; });
    }
  }

  Future<void> _finishOnboarding() async {
    // Save zones if any selected
    if (_zones.isNotEmpty) {
      try { await _api.saveOnboardingZones(_zones); } catch (_) {}
    }

    // Save name
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    await prefs.setString('user_name', _nameController.text.trim());

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }
}
