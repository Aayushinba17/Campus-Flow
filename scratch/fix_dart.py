import re

def fix_file(path, func):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    new_text = func(text)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_text)

def fix_api_service(text):
    text = text.replace('Future<String> get await _uid async => UserService.getUserId();', 'Future<String> get _uid async => await UserService.getUserId();')
    text = re.sub(r'\$await await _uid', r'${await _uid}', text)
    text = re.sub(r'await await _uid', r'await _uid', text)
    return text
fix_file('lib/services/api_service.dart', fix_api_service)

def fix_notes_screen(text):
    return text.replace("setState(() => _searchResults = res['results'] ?? []);", "setState(() => _searchResults = res);")
fix_file('lib/screens/notes_screen.dart', fix_notes_screen)

def fix_constants(text):
    lines = text.split('\n')
    for i, line in enumerate(lines):
        if 'static const String notesSemanticSearch' in line and i > 60:
            lines[i] = ''
    return '\n'.join(lines)
fix_file('lib/utils/constants.dart', fix_constants)

def fix_onboarding(text):
    lines = text.split('\n')
    for i, line in enumerate(lines):
        if "import 'package:geolocator/geolocator.dart';" in line and i > 10:
            lines[i] = ''
    return '\n'.join(lines)
fix_file('lib/screens/onboarding_screen.dart', fix_onboarding)

def fix_location(text):
    return text.replace('LocationAccuracy.balanced', 'LocationAccuracy.medium')
fix_file('lib/services/location_service.dart', fix_location)

def fix_classroom(text):
    return text.replace('AppConstants.userId', 'await UserService.getUserId()')
fix_file('lib/services/classroom_service.dart', fix_classroom)

def fix_proactive(text):
    return text.replace('AppConstants.userId', 'await UserService.getUserId()')
fix_file('lib/services/proactive_alert_service.dart', fix_proactive)
