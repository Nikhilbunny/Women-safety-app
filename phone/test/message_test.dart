import 'package:flutter_test/flutter_test.dart';
import 'package:safetyapp/message_builder.dart';

void main() {
  group('normalizePhone', () {
    test('accepts and cleans common formats', () {
      expect(normalizePhone('+91 98765-43210'), '+919876543210');
      expect(normalizePhone('(040) 2345 6789'), '04023456789');
    });
    test('rejects junk', () {
      expect(normalizePhone('abc'), isNull);
      expect(normalizePhone('12345'), isNull);
      expect(normalizePhone(''), isNull);
    });
  });

  group('buildSosMessage', () {
    test('includes coordinates and map link when location known', () {
      final m = buildSosMessage(
        name: 'Asha',
        time: DateTime(2026, 10, 10, 11, 53),
        source: 'watch',
        lat: 17.385,
        lng: 78.4867,
        accuracyMeters: 12.4,
      );
      expect(m, contains('Asha needs help'));
      expect(m, contains('10 Oct 2026 11:53'));
      expect(m, contains('17.38500, 78.48670'));
      expect(m, contains('https://maps.google.com/?q=17.38500,78.48670'));
      expect(m, contains('via watch'));
    });

    test('still produces a useful message without location', () {
      final m = buildSosMessage(name: 'Asha', time: DateTime(2026, 1, 2, 3, 4), source: 'phone');
      expect(m, contains('unavailable'));
      expect(m, isNot(contains('maps.google.com')));
    });

    test('uses GSM-7 safe characters only (keeps SMS short)', () {
      final m = buildSosMessage(
        name: 'Asha',
        time: DateTime(2026, 1, 2),
        source: 'phone',
        lat: 1.0,
        lng: 2.0,
        accuracyMeters: 5,
      );
      expect(m.runes.every((r) => r < 128), isTrue);
    });
  });
}
