import 'package:flutter_test/flutter_test.dart';
import 'package:safetyapp/geo.dart';
import 'package:safetyapp/places.dart';

void main() {
  group('geo', () {
    test('distance between two known points is about right', () {
      // Hyderabad Charminar to Hussain Sagar is roughly 5 km.
      final d = distanceMeters(17.3616, 78.4747, 17.4239, 78.4738);
      expect(d, inInclusiveRange(6500, 7300));
    });
    test('zero distance for same point', () {
      expect(distanceMeters(10, 20, 10, 20), closeTo(0, 0.001));
    });
    test('bearing north and east', () {
      expect(bearingDegrees(0, 0, 1, 0), closeTo(0, 0.5));
      expect(bearingDegrees(0, 0, 0, 1), closeTo(90, 0.5));
    });
    test('compass names', () {
      expect(compass(0), 'N');
      expect(compass(359), 'N');
      expect(compass(90), 'E');
      expect(compass(225), 'SW');
    });
    test('formatDistance', () {
      expect(formatDistance(420), '420 m');
      expect(formatDistance(1520), '1.5 km');
    });
  });

  group('parseOverpass', () {
    const body = '''
{"elements":[
 {"type":"node","id":1,"lat":17.1,"lon":78.1,"tags":{"amenity":"hospital","name":"City Hospital","phone":"+91 40 1234"}},
 {"type":"way","id":2,"center":{"lat":17.2,"lon":78.2},"tags":{"amenity":"police"}},
 {"type":"node","id":3,"lat":17.3,"lon":78.3,"tags":{"entrance":"emergency"}},
 {"type":"node","id":4,"lat":17.4,"lon":78.4,"tags":{"shop":"bakery"}},
 {"type":"way","id":5,"tags":{"amenity":"hospital"}}
]}''';
    test('classifies, uses centre for ways, skips junk', () {
      final list = parseOverpass(body);
      expect(list.length, 3);
      final h = list.firstWhere((p) => p.kind == PlaceKind.hospital);
      expect(h.name, 'City Hospital');
      expect(h.phone, '+91 40 1234');
      final pol = list.firstWhere((p) => p.kind == PlaceKind.police);
      expect(pol.lat, 17.2);
      expect(pol.name, 'Police station');
      expect(list.any((p) => p.kind == PlaceKind.exit), isTrue);
    });
    test('handles empty or odd input', () {
      expect(parseOverpass('{"elements":[]}'), isEmpty);
      expect(parseOverpass('[]'), isEmpty);
    });
    test('query mentions all three kinds', () {
      final q = buildOverpassQuery(1.5, 2.5);
      expect(q, contains('hospital'));
      expect(q, contains('police'));
      expect(q, contains('emergency'));
      expect(q, contains('around:5000,1.5,2.5'));
    });
  });
}
