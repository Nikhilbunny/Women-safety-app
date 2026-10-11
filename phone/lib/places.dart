import 'dart:convert';

/// Pure Dart (no Flutter imports) so parsing can be unit tested.

enum PlaceKind { hospital, police, exit }

String kindLabel(PlaceKind k) {
  switch (k) {
    case PlaceKind.hospital:
      return 'Hospital';
    case PlaceKind.police:
      return 'Police station';
    case PlaceKind.exit:
      return 'Emergency exit / assembly point';
  }
}

class Place {
  final String id;
  final PlaceKind kind;
  final String name;
  final double lat;
  final double lng;
  final String? phone;

  const Place({
    required this.id,
    required this.kind,
    required this.name,
    required this.lat,
    required this.lng,
    this.phone,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'lat': lat,
        'lng': lng,
        'phone': phone,
      };

  factory Place.fromMap(Map<String, Object?> m) => Place(
        id: m['id'] as String,
        kind: PlaceKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => PlaceKind.hospital),
        name: m['name'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        phone: m['phone'] as String?,
      );
}

PlaceKind? _classify(Map<String, dynamic> tags) {
  if (tags['amenity'] == 'hospital') return PlaceKind.hospital;
  if (tags['amenity'] == 'police') return PlaceKind.police;
  if (tags['entrance'] == 'emergency' ||
      tags['door'] == 'emergency' ||
      tags['emergency'] == 'assembly_point' ||
      tags['highway'] == 'emergency_access_point') {
    return PlaceKind.exit;
  }
  return null;
}

/// Parses an OpenStreetMap Overpass JSON response into places.
/// Items without coordinates or without a recognised tag are skipped.
List<Place> parseOverpass(String body) {
  final data = jsonDecode(body);
  if (data is! Map<String, dynamic>) return const [];
  final elements = data['elements'];
  if (elements is! List) return const [];

  final result = <String, Place>{};
  for (final e in elements) {
    if (e is! Map<String, dynamic>) continue;
    final rawTags = e['tags'];
    if (rawTags is! Map) continue;
    final tags = rawTags.map((k, v) => MapEntry(k.toString(), v));
    final kind = _classify(tags);
    if (kind == null) continue;

    num? lat = e['lat'] as num?;
    num? lng = e['lon'] as num?;
    final center = e['center'];
    if ((lat == null || lng == null) && center is Map) {
      lat = center['lat'] as num?;
      lng = center['lon'] as num?;
    }
    if (lat == null || lng == null) continue;

    final id = '${e['type']}${e['id']}';
    final name = (tags['name'] ?? tags['name:en'] ?? tags['operator'] ?? kindLabel(kind)).toString();
    final phone = (tags['phone'] ?? tags['contact:phone'])?.toString();
    result[id] = Place(
      id: id,
      kind: kind,
      name: name,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      phone: phone,
    );
  }
  return result.values.toList();
}

/// Overpass QL: hospitals and police within [radius] m, exits within [exitRadius] m.
String buildOverpassQuery(double lat, double lng, {int radius = 5000, int exitRadius = 1500}) {
  final c = '$lat,$lng';
  return '[out:json][timeout:25];'
      '(nwr["amenity"="hospital"](around:$radius,$c););out center tags 40;'
      '(nwr["amenity"="police"](around:$radius,$c););out center tags 40;'
      '(nwr["entrance"="emergency"](around:$exitRadius,$c);'
      'nwr["door"="emergency"](around:$exitRadius,$c);'
      'nwr["emergency"="assembly_point"](around:$exitRadius,$c);'
      'nwr["highway"="emergency_access_point"](around:$exitRadius,$c););out center tags 40;';
}
