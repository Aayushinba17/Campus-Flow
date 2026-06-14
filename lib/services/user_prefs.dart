import 'package:shared_preferences/shared_preferences.dart';

class UserPrefs {
  static const _kNotifBatchSize = 'notif_batch_size';
  static const _kDigestHour = 'digest_hour';
  static const _kWaterReminderMins = 'water_reminder_mins';
  static const _kPreClassReminderMins = 'pre_class_reminder_mins';
  static const _kZoneRadius = 'zone_radius';

  static Future<int> getNotifBatchSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kNotifBatchSize) ?? 50;
  }

  static Future<void> setNotifBatchSize(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kNotifBatchSize, value);
  }

  static Future<int> getDigestHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kDigestHour) ?? 8;
  }

  static Future<void> setDigestHour(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDigestHour, value);
  }

  static Future<int> getWaterReminderMins() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kWaterReminderMins) ?? 90;
  }

  static Future<void> setWaterReminderMins(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kWaterReminderMins, value);
  }

  static Future<int> getPreClassReminderMins() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kPreClassReminderMins) ?? 30;
  }

  static Future<void> setPreClassReminderMins(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPreClassReminderMins, value);
  }

  static Future<int> getZoneRadius() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kZoneRadius) ?? 150;
  }

  static Future<void> setZoneRadius(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kZoneRadius, value);
  }
}
