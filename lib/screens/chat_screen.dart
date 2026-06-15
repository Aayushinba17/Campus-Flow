import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/api_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();

  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  bool _listening = false;
  String? _sessionId;

  final _quickPrompts = [
    'What do I have today?',
    'What\'s due this week?',
    'Am I free this afternoon?',
    'Summarize my recent updates',
    'How many days until my next exam?',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _api.getChatHistory();
      final List<Map<String, dynamic>> loaded = [];
      for (final h in history.take(20)) {
        if (h['user_msg'] != null) {
          loaded.add({'role': 'user', 'content': h['user_msg'], 'ts': h['created_at'] ?? ''});
        }
        if (h['assistant_msg'] != null) {
          loaded.add({'role': 'assistant', 'content': h['assistant_msg'], 'ts': h['created_at'] ?? ''});
        }
      }
      setState(() => _messages = loaded);
    } catch (_) {}
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add({'role': 'user', 'content': text, 'ts': DateTime.now().toIso8601String()});
      _loading = true;
    });
    _scrollToBottom();

    try {
      final result = await _api.sendChatMessage(text, sessionId: _sessionId);
      _sessionId = result['session_id'];
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': result['response'] ?? 'Sorry, I couldn\'t get a response.',
          'ts': DateTime.now().toIso8601String(),
        });
        _loading = false;
      });
    } catch (e) {
      final errMsg = e.toString().contains('SocketException') || e.toString().contains('TimeoutException')
          ? 'Connection error. Check your internet.'
          : 'Error: ${e.toString().replaceAll('Exception: ', '')}';
      setState(() {
        _messages.add({'role': 'assistant', 'content': errMsg, 'ts': ''});
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone not available')));
      return;
    }
    setState(() => _listening = true);
    _speech.listen(onResult: (result) {
      if (result.finalResult) {
        setState(() => _listening = false);
        _sendMessage(result.recognizedWords);
      }
    });
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _listening = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CampusFlow AI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('Ask anything about your schedule, notes, updates',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => setState(() { _messages = []; _sessionId = null; }),
            tooltip: 'New conversation',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Quick prompts ────────────────────────────────────────
          if (_messages.isEmpty)
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ActionChip(
                  label: Text(_quickPrompts[i], style: const TextStyle(fontSize: 12)),
                  onPressed: () => _sendMessage(_quickPrompts[i]),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),

          // ── Messages ──────────────────────────────────────────────
          Expanded(
            child: _messages.isEmpty
              ? _emptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_loading ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == _messages.length) return _typingIndicator();
                    return _messageBubble(_messages[i]);
                  },
                ),
          ),

          // ── Input bar ────────────────────────────────────────────
          _inputBar(),
        ],
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28, height: 28,
              decoration: const BoxDecoration(
                color: Color(0xFFE8592B), shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFFE8592B) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
              ),
              child: Text(msg['content'] ?? '',
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF1A1A2E),
                  fontSize: 14, height: 1.5,
                )),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _typingIndicator() {
    return Row(children: [
      Container(
        width: 28, height: 28,
        decoration: const BoxDecoration(color: Color(0xFFE8592B), shape: BoxShape.circle),
        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 14),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          _dot(0), const SizedBox(width: 4),
          _dot(150), const SizedBox(width: 4),
          _dot(300),
        ]),
      ),
    ]);
  }

  Widget _dot(int delayMs) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.3, end: 1.0),
    duration: const Duration(milliseconds: 600),
    curve: Curves.easeInOut,
    builder: (_, v, __) => Opacity(
      opacity: v,
      child: Container(width: 8, height: 8,
        decoration: const BoxDecoration(color: Color(0xFFE8592B), shape: BoxShape.circle)),
    ),
  );

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(children: [
        // Mic button
        GestureDetector(
          onLongPressStart: (_) => _startListening(),
          onLongPressEnd:   (_) => _stopListening(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _listening ? Colors.red : const Color(0xFFE8592B).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _listening ? Icons.mic : Icons.mic_none_outlined,
              color: _listening ? Colors.white : const Color(0xFFE8592B),
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Text field
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: _listening ? 'Listening...' : 'Ask about your schedule, notes...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              filled: true,
              fillColor: const Color(0xFFF5F5F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onSubmitted: _sendMessage,
            textInputAction: TextInputAction.send,
          ),
        ),
        const SizedBox(width: 10),
        // Send button
        GestureDetector(
          onTap: () => _sendMessage(_controller.text),
          child: Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(color: Color(0xFFE8592B), shape: BoxShape.circle),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFE8592B).withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.auto_awesome, color: Color(0xFFE8592B), size: 32),
      ),
      const SizedBox(height: 16),
      const Text('Ask me anything', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text('Your schedule, notes, deadlines, updates',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
      const SizedBox(height: 4),
      Text('Hold 🎙 to speak', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
    ]),
  );
}