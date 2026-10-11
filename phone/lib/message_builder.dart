/// Pure Dart helpers (no Flutter imports) so they can be unit tested easily.

/// Strips spaces, dashes and brackets; returns null if the number is not
/// plausible (7-15 digits, optional leading +).
String? normalizePhone(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(cleaned)) return null;
  return cleaned;
}

/// Builds the SOS text. Uses plain GSM-7 characters only so the message fits
/// in as few SMS segments as possible. Raw coordinates are included so that a
/// recipient without internet can still read the position; the map link is a
/// bonus for recipients who are online.
String buildSosMessage({
  required String name,
  required DateTime time,
  required String source,
  double? lat,
  double? lng,
  double? accuracyMeters,
  bool locationIsStale = false,
}) {
  final b = StringBuffer();
  b.writeln('EMERGENCY - $name needs help.');
  b.writeln('Time: ${_fmt(time)}');
  if (lat != null && lng != null) {
    final acc = accuracyMeters == null ? '' : ' (approx ${accuracyMeters.round()} m)';
    final stale = locationIsStale ? ' [last known]' : '';
    b.writeln('Location: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}$acc$stale');
    b.writeln('Map: https://maps.google.com/?q=${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}');
  } else {
    b.writeln('Location: unavailable. Please call now.');
  }
  b.write('Sent by Safety App via $source.');
  return b.toString();
}

String _fmt(DateTime t) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)} ${m[t.month - 1]} ${t.year} ${two(t.hour)}:${two(t.minute)}';
}
