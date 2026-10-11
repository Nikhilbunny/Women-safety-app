import 'package:http/http.dart' as http;

import 'db.dart';
import 'places.dart';

/// Looks up nearby hospitals, police stations and emergency exits from
/// OpenStreetMap (free, no API key). Results are cached in the local database
/// so the list keeps working with no internet.
class PlacesService {
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  /// Needs internet. Throws if every server fails.
  static Future<List<Place>> fetch(double lat, double lng) async {
    final query = buildOverpassQuery(lat, lng);
    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final res = await http
            .post(
              Uri.parse(endpoint),
              headers: {'User-Agent': 'SafetyApp/0.1 (student project)'},
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final places = parseOverpass(res.body);
          await AppDb.instance.savePlaces(places, lat, lng);
          return places;
        }
        lastError = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('Could not reach map servers: $lastError');
  }
}
