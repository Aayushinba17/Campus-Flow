import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  /// Request all required permissions at once
  static Future<Map<Permission, PermissionStatus>> requestAll() async {
    return await [
      Permission.notification,
      Permission.microphone,
      Permission.camera,
      Permission.storage,
      Permission.location,
    ].request();
  }

  /// Check if all critical permissions are granted
  static Future<bool> hasAllCritical() async {
    final notification = await Permission.notification.isGranted;
    final microphone = await Permission.microphone.isGranted;
    return notification && microphone;
  }

  /// Check single permission
  static Future<bool> check(Permission permission) async {
    return await permission.isGranted;
  }

  /// Request single permission with rationale handling
  static Future<bool> requestSingle(Permission permission) async {
    if (await permission.isGranted) return true;
    final status = await permission.request();
    return status.isGranted;
  }

  /// Check if notification listener access is available
  static Future<bool> hasNotificationListener() async {
    return await Permission.notification.isGranted;
  }

  /// Check location permission
  static Future<bool> hasLocation() async {
    return await Permission.location.isGranted;
  }

  /// Open app settings for permanently denied permissions
  static Future<void> openSettings() async {
    await openAppSettings();
  }
}
