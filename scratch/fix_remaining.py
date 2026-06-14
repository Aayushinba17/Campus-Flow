import re

def process_file(path, func):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    new_text = func(text)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_text)

def fix_main(t):
    return t.replace(", isInDebugMode: false", "").replace(", isInDebugMode: true", "")

def fix_chat(t):
    t = t.replace("final h = _messages.firstWhere((x) => x['content'] == m['content'], orElse: () => {});", "_messages.firstWhere((x) => x['content'] == m['content'], orElse: () => {});")
    t = t.replace("      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(content: Text('Microphone not available')));", "      if (!mounted) return;\n      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(content: Text('Microphone not available')));")
    return t

def fix_routine(t):
    return t.replace("if (mounted) { Navigator.pop(ctx); _loadData(); }", "if (ctx.mounted) { Navigator.pop(ctx); _loadData(); }")

def fix_schedule(t):
    return t.replace("  Map<String, dynamic>? _freeSlots;\n", "")

def fix_settings(t):
    t = t.replace("await _api.syncClassroom();\n            ScaffoldMessenger.of(context).showSnackBar(", "await _api.syncClassroom();\n            if (!mounted) return;\n            ScaffoldMessenger.of(context).showSnackBar(")
    t = t.replace("perm = await Geolocator.requestPermission();\n    }\n    if (perm != LocationPermission.always", "perm = await Geolocator.requestPermission();\n    }\n    if (!mounted) return;\n    if (perm != LocationPermission.always")
    t = t.replace("lng: pos.longitude);\n    ScaffoldMessenger.of(context).showSnackBar(", "lng: pos.longitude);\n    if (!mounted) return;\n    ScaffoldMessenger.of(context).showSnackBar(")
    t = t.replace("final result = await _api.syncClassroom();\n                      final created = (result['tasks_created'] as List?)?.length ?? 0;\n                      ScaffoldMessenger.of(context).showSnackBar(", "final result = await _api.syncClassroom();\n                      final created = (result['tasks_created'] as List?)?.length ?? 0;\n                      if (!mounted) return;\n                      ScaffoldMessenger.of(context).showSnackBar(")
    return t

def fix_classroom(t):
    return t.replace("if (ok) {\n      setState(() => entry['undone'] = true);\n      ScaffoldMessenger.of(context).showSnackBar(", "if (ok) {\n      if (!mounted) return;\n      setState(() => entry['undone'] = true);\n      ScaffoldMessenger.of(context).showSnackBar(")

def fix_task_board(t):
    return t.replace("listenFor: const Duration(seconds: 30),", "listenOptions: SpeechListenOptions(listenFor: const Duration(seconds: 30)),")

process_file('lib/main.dart', fix_main)
process_file('lib/screens/chat_screen.dart', fix_chat)
process_file('lib/screens/routine_screen.dart', fix_routine)
process_file('lib/screens/schedule_screen.dart', fix_schedule)
process_file('lib/screens/settings_screen.dart', fix_settings)
process_file('lib/services/classroom_service.dart', fix_classroom)
process_file('lib/screens/task_board_screen.dart', fix_task_board)

print("Done")
