import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local SQLite store. Everything the app needs lives here, so it keeps
/// working with no network at all.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'safety.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (d, v) async {
        await d.execute(
            'CREATE TABLE contacts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT NOT NULL, relation TEXT)');
        await d.execute(
            'CREATE TABLE outbox(id INTEGER PRIMARY KEY AUTOINCREMENT, numbers TEXT NOT NULL, message TEXT NOT NULL, created_at INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0)');
        await d.execute(
            'CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT, time INTEGER NOT NULL, lat REAL, lng REAL, source TEXT NOT NULL, delivered INTEGER NOT NULL)');
        await d.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT)');
      },
    );
  }

  // ---- contacts ----
  Future<List<Contact>> contacts() async {
    final rows = await (await _database).query('contacts', orderBy: 'id');
    return rows.map(Contact.fromMap).toList();
  }

  Future<void> addContact(Contact c) async {
    final m = c.toMap()..remove('id');
    await (await _database).insert('contacts', m);
  }

  Future<void> deleteContact(int id) async {
    await (await _database).delete('contacts', where: 'id = ?', whereArgs: [id]);
  }

  // ---- outbox (messages waiting for cellular signal) ----
  Future<void> enqueue(List<String> numbers, String message) async {
    if (numbers.isEmpty) return;
    await (await _database).insert('outbox', {
      'numbers': numbers.join(','),
      'message': message,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
  }

  Future<List<OutboxItem>> outbox() async {
    final rows = await (await _database).query('outbox', orderBy: 'id');
    return rows.map(OutboxItem.fromMap).toList();
  }

  Future<void> removeOutbox(int id) async {
    await (await _database).delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  /// After a partial retry only the numbers that still failed stay queued.
  Future<void> updateOutbox(int id, List<String> remaining, int attempts) async {
    await (await _database).update(
      'outbox',
      {'numbers': remaining.join(','), 'attempts': attempts},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- event log ----
  Future<void> logEvent({
    required DateTime time,
    double? lat,
    double? lng,
    required String source,
    required bool delivered,
  }) async {
    await (await _database).insert('events', {
      'time': time.millisecondsSinceEpoch,
      'lat': lat,
      'lng': lng,
      'source': source,
      'delivered': delivered ? 1 : 0,
    });
  }

  Future<List<SosEvent>> events({int limit = 20}) async {
    final rows = await (await _database).query('events', orderBy: 'id DESC', limit: limit);
    return rows.map(SosEvent.fromMap).toList();
  }

  // ---- settings ----
  Future<String?> getSetting(String key) async {
    final rows = await (await _database).query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await (await _database).insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
