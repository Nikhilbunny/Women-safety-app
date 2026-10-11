class Contact {
  final int? id;
  final String name;
  final String phone;
  final String relation;

  const Contact({this.id, required this.name, required this.phone, this.relation = ''});

  Map<String, Object?> toMap() => {'id': id, 'name': name, 'phone': phone, 'relation': relation};

  factory Contact.fromMap(Map<String, Object?> m) => Contact(
        id: m['id'] as int?,
        name: m['name'] as String,
        phone: m['phone'] as String,
        relation: (m['relation'] as String?) ?? '',
      );
}

class SosEvent {
  final int? id;
  final DateTime time;
  final double? lat;
  final double? lng;
  final String source; // phone | watch | shake
  final bool delivered; // false = queued in outbox

  const SosEvent({
    this.id,
    required this.time,
    this.lat,
    this.lng,
    required this.source,
    required this.delivered,
  });

  factory SosEvent.fromMap(Map<String, Object?> m) => SosEvent(
        id: m['id'] as int?,
        time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        lat: m['lat'] as double?,
        lng: m['lng'] as double?,
        source: m['source'] as String,
        delivered: (m['delivered'] as int) == 1,
      );
}

class OutboxItem {
  final int id;
  final List<String> numbers;
  final String message;
  final DateTime createdAt;
  final int attempts;

  const OutboxItem({
    required this.id,
    required this.numbers,
    required this.message,
    required this.createdAt,
    required this.attempts,
  });

  factory OutboxItem.fromMap(Map<String, Object?> m) => OutboxItem(
        id: m['id'] as int,
        numbers: (m['numbers'] as String).split(','),
        message: m['message'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        attempts: m['attempts'] as int,
      );
}
