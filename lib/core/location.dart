import 'package:geolocator/geolocator.dart';

import '../data/models/customer.dart';

/// Device location, or null when unavailable / denied (same as the web `getCurrentLocation`). Never throws.
Future<GeoPoint?> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever)
      return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (latitude: p.latitude, longitude: p.longitude);
  } catch (_) {
    return null;
  }
}
