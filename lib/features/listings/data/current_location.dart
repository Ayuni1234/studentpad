import 'package:geolocator/geolocator.dart';

/// Requests the device position only after a user action and returns a coarse
/// area string; it does not send the coordinates to a geocoding service.
Future<String> getApproximateCurrentLocation() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const _LocationAccessException(
        'Allow location access in your browser to use this option.');
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 15),
    ),
  );
  return 'Approx. GPS area: ${position.latitude.toStringAsFixed(2)}, '
      '${position.longitude.toStringAsFixed(2)}';
}

class _LocationAccessException implements Exception {
  const _LocationAccessException(this.message);
  final String message;

  @override
  String toString() => message;
}
