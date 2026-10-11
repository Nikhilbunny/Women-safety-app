import 'dart:math';

/// Pure Dart geometry helpers (no Flutter imports) so they can be unit tested.

double _rad(double deg) => deg * pi / 180.0;

/// Great-circle distance in metres (haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return 2 * r * asin(min(1.0, sqrt(a)));
}

/// Initial bearing from point 1 to point 2, 0..360 degrees clockwise from north.
double bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
  final dLng = _rad(lng2 - lng1);
  final y = sin(dLng) * cos(_rad(lat2));
  final x = cos(_rad(lat1)) * sin(_rad(lat2)) -
      sin(_rad(lat1)) * cos(_rad(lat2)) * cos(dLng);
  return (atan2(y, x) * 180.0 / pi + 360.0) % 360.0;
}

String compass(double degrees) {
  const names = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  final i = (((degrees + 22.5) % 360.0) / 45.0).floor();
  return names[i % 8];
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
