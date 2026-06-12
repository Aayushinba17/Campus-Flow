import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreetingCard(),
              const SizedBox(height: 16),
              _buildScheduleCard(),
              const SizedBox(height: 16),
              _buildNotificationDigestCard(),
              const SizedBox(height: 16),
              _buildWellnessCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildGreetingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('Good morning, Rahul 👋',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          SizedBox(height: 8),
          Text('Here\'s your day — 3 classes, 2 deadlines detected.',
              style: TextStyle(fontSize: 14, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildScheduleCard() {
    return _card(
      title: "Today's Schedule",
      icon: Icons.calendar_today,
      child: Column(
        children: [
          _scheduleItem('9:00 AM', 'Data Structures', 'Room 204'),
          _scheduleItem('11:00 AM', 'Operating Systems', 'Room 101'),
          _scheduleItem('2:00 PM', 'DBMS Lab', 'Lab 3'),
        ],
      ),
    );
  }

  Widget _scheduleItem(String time, String subject, String room) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(time, style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(subject, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          Text(room, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildNotificationDigestCard() {
    return _card(
      title: 'Notification Digest',
      icon: Icons.notifications_outlined,
      child: Column(
        children: const [
          _DigestItem(app: 'WhatsApp', summary: '47 messages — 2 assignment deadlines detected', urgent: true),
          _DigestItem(app: 'Gmail', summary: 'Internship confirmation from company', urgent: false),
          _DigestItem(app: 'Teams', summary: 'Class cancelled tomorrow', urgent: false),
        ],
      ),
    );
  }

  Widget _buildWellnessCard() {
    return _card(
      title: 'Wellness',
      icon: Icons.favorite_outline,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _wellnessStat('💧', 'Water', '4/8 cups'),
          _wellnessStat('😴', 'Sleep', '6.5 hrs'),
          _wellnessStat('🧘', 'Break', 'Due now'),
        ],
      ),
    );
  }

  Widget _wellnessStat(String emoji, String label, String value) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _card({required String title, required IconData icon, required Widget child}) {
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
              Icon(icon, color: const Color(0xFF6C63FF), size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: const Color(0xFF1A1A2E),
      selectedItemColor: const Color(0xFF6C63FF),
      unselectedItemColor: Colors.white38,
      type: BottomNavigationBarType.fixed,
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month_outlined), label: 'Schedule'),
        BottomNavigationBarItem(icon: Icon(Icons.inbox_outlined), label: 'Messages'),
        BottomNavigationBarItem(icon: Icon(Icons.note_outlined), label: 'Notes'),
        BottomNavigationBarItem(icon: Icon(Icons.chat_outlined), label: 'Chat'),
      ],
    );
  }
}

class _DigestItem extends StatelessWidget {
  final String app;
  final String summary;
  final bool urgent;

  const _DigestItem({required this.app, required this.summary, required this.urgent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (urgent)
            Container(
              margin: const EdgeInsets.only(top: 4, right: 8),
              width: 6, height: 6,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            )
          else
            const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(summary, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}