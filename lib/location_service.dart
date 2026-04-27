import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception("GPS belum aktif. Silakan aktifkan Location.");
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception("Izin lokasi ditolak.");
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception("Izin lokasi ditolak permanen. Buka settings untuk mengaktifkan.");
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  static double distanceInMeters(
    double userLat,
    double userLng,
    double officeLat,
    double officeLng,
  ) {
    return Geolocator.distanceBetween(userLat, userLng, officeLat, officeLng);
  }
}
