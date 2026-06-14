import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

class LocationService {
  static final _api = ApiService();

  static Future<void> updateCurrentZone() async {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      await _api.detectZoneFromGPS(pos.latitude, pos.longitude);
    } catch (_) {}
  }
}