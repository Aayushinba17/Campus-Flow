import re

def fix_classroom(text):
    text = text.replace("final String _uid  = await UserService.getUserId();\n", "")
    text = re.sub(r'\$_uid', r'${await UserService.getUserId()}', text)
    text = re.sub(r'\b_uid\b', r'(await UserService.getUserId())', text)
    if "import '../services/user_service.dart';" not in text:
        text = text.replace("import '../utils/constants.dart';", "import '../utils/constants.dart';\nimport '../services/user_service.dart';")
    return text

with open('lib/services/classroom_service.dart', 'r', encoding='utf-8') as f:
    text = f.read()
with open('lib/services/classroom_service.dart', 'w', encoding='utf-8') as f:
    f.write(fix_classroom(text))

def fix_proactive(text):
    text = text.replace("final String _uid  = await UserService.getUserId();\n", "")
    text = re.sub(r'\$_uid', r'${await UserService.getUserId()}', text)
    text = re.sub(r'\b_uid\b', r'(await UserService.getUserId())', text)
    if "import '../services/user_service.dart';" not in text:
        text = text.replace("import '../utils/constants.dart';", "import '../utils/constants.dart';\nimport '../services/user_service.dart';")
    return text

with open('lib/services/proactive_alert_service.dart', 'r', encoding='utf-8') as f:
    text = f.read()
with open('lib/services/proactive_alert_service.dart', 'w', encoding='utf-8') as f:
    f.write(fix_proactive(text))
