import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class UserService {
  static const _kUserIdKey = 'user_id';
  static const _kUserNameKey = 'user_name';
  static String? _cachedId;
  static String? _cachedName;

  static Future<String> getUserId() async {
    if (_cachedId != null) return _cachedId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kUserIdKey);
    if (id == null || id.isEmpty) {
      id = 'user_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
      await prefs.setString(_kUserIdKey, id);
    }
    _cachedId = id;
    return id;
  }

  static Future<String> getUserName() async {
    if (_cachedName != null) return _cachedName!;
    final prefs = await SharedPreferences.getInstance();
    _cachedName = prefs.getString(_kUserNameKey) ?? 'Student';
    return _cachedName!;
  }

  static Future<void> setUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserNameKey, name.trim());
    _cachedName = name.trim();
  }
}