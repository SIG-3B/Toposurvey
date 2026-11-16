import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum LocationAccess {
  ready('GPS siap digunakan'),
  disabled('Layanan lokasi nonaktif'),
  denied('Izin lokasi belum diberikan'),
  deniedForever('Izin lokasi diblokir'),
  unavailable('Status GPS tidak dapat diperiksa');

  const LocationAccess(this.label);

  final String label;
}

class LocationService {
  const LocationService();

  Future<LocationAccess> checkAccess({bool requestPermission = false}) async {
    // On the web, starting the position stream prompts the user and reports
    // the difference between a denied permission and an unavailable position.
    if (kIsWeb && requestPermission) return LocationAccess.ready;

    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.disabled;
    }

    var permission = await Geolocator.checkPermission();
    if (requestPermission && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return switch (permission) {
      LocationPermission.always ||
      LocationPermission.whileInUse => LocationAccess.ready,
      LocationPermission.denied => LocationAccess.denied,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.unableToDetermine => LocationAccess.unavailable,
    };
  }

  Stream<Position> watchPositions() => Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      intervalDuration: const Duration(seconds: 2),
      maxUpdateAge: Duration.zero,
      timeLimit: const Duration(seconds: 20),
    ),
  );

  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
