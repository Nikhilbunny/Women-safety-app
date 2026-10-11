import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db.dart';
import 'message_builder.dart';

/// Core offline SOS pipeline:
///   GPS (works without internet) -> SMS (works without internet, needs cell
///   signal) -> if that fails, park the message in the local outbox and retry.
class SosService {
  SosService._();
  static final SosService instance = SosService._();

  static const _native = MethodChannel('safety/native');

  final ValueNotifier<String> status = ValueNotifier<String>('Ready');
  bool _busy = false;

  Future<void> init() async {
    // The watch (via native code) asks the phone to send an SOS.
    _native.setMethodCallHandler((call) async {
      if (call.method == 'watchSos') {
        await trigger(source: 'watch');
      }
      return null;
    });
    await syncNative();
    await _importNativeEvents();
    await flushOutbox();
  }

  /// Mirrors contacts + name into native storage so the Android service can
  /// send an SOS for the watch even when the Flutter UI is not running.
  Future<void> syncNative() async {
    if (!Platform.isAndroid) return;
    final contacts = await AppDb.instance.contacts();
    final name = await AppDb.instance.getSetting('user_name') ?? '';
    try {
      await _native.invokeMethod('syncState', {
        'contactsJson': jsonEncode(contacts.map((c) => c.phone).toList()),
        'userName': name,
      });
    } on PlatformException catch (_) {}
  }

  /// SOS events the native service handled while the app was closed.
  Future<void> _importNativeEvents() async {
    if (!Platform.isAndroid) return;
    try {
      final raw = await _native.invokeMethod<String>('drainEvents');
      if (raw == null || raw.isEmpty) return;
      for (final e in jsonDecode(raw) as List<dynamic>) {
        final m = e as Map<String, dynamic>;
        await AppDb.instance.logEvent(
          time: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
          lat: (m['lat'] as num?)?.toDouble(),
          lng: (m['lng'] as num?)?.toDouble(),
          source: 'watch',
          delivered: m['delivered'] as bool,
        );
        if (m['delivered'] != true) {
          final numbers = (m['failed'] as List<dynamic>).cast<String>();
          await AppDb.instance.enqueue(numbers, m['message'] as String);
        }
      }
    } on PlatformException catch (_) {}
  }

  Future<Position?> _bestPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return Geolocator.getLastKnownPosition();
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      // GPS can be slow indoors; a recent cached fix is better than nothing.
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// Returns true if the alert was handed to the radio for every contact.
  Future<bool> trigger({required String source}) async {
    if (_busy) return false;
    _busy = true;
    try {
      final contacts = await AppDb.instance.contacts();
      if (contacts.isEmpty) {
        status.value = 'Add at least one emergency contact first';
        return false;
      }
      status.value = 'Getting location...';
      final pos = await _bestPosition();
      final stale = pos != null && DateTime.now().difference(pos.timestamp).inSeconds > 60;
      final name = (await AppDb.instance.getSetting('user_name'))?.trim();
      final now = DateTime.now();
      final message = buildSosMessage(
        name: (name == null || name.isEmpty) ? 'Someone' : name,
        time: now,
        source: source,
        lat: pos?.latitude,
        lng: pos?.longitude,
        accuracyMeters: pos?.accuracy,
        locationIsStale: stale,
      );

      status.value = 'Sending alerts...';
      final numbers = contacts.map((c) => c.phone).toList();
      final failed = await _sendSms(numbers, message);
      if (failed.isNotEmpty) {
        await AppDb.instance.enqueue(failed, message);
      }
      await AppDb.instance.logEvent(
        time: now,
        lat: pos?.latitude,
        lng: pos?.longitude,
        source: source,
        delivered: failed.isEmpty,
      );
      status.value = failed.isEmpty
          ? (Platform.isIOS ? 'Message ready - tap Send in Messages' : 'SOS sent to ${numbers.length} contact(s)')
          : 'No signal - alert saved, will retry automatically';
      return failed.isEmpty;
    } finally {
      _busy = false;
    }
  }

  /// Returns the numbers that could NOT be sent.
  Future<List<String>> _sendSms(List<String> numbers, String message) async {
    if (Platform.isAndroid) {
      try {
        final res = await _native.invokeMethod<List<dynamic>>('sendSms', {
          'numbers': numbers,
          'message': message,
        });
        return (res ?? numbers).cast<String>();
      } on PlatformException catch (_) {
        return numbers;
      }
    }
    // iOS does not allow silent SMS. Open the composer pre-filled; the user
    // must press Send. This is an OS restriction, not something to work around.
    final uri = Uri.parse('sms:${numbers.join(",")}&body=${Uri.encodeComponent(message)}');
    final ok = await launchUrl(uri);
    return ok ? <String>[] : numbers;
  }

  /// Retries queued alerts. Safe to call often (app start, resume, timer).
  Future<void> flushOutbox() async {
    final items = await AppDb.instance.outbox();
    for (final item in items) {
      final stillFailed = await _sendSms(item.numbers, item.message);
      if (stillFailed.isEmpty) {
        await AppDb.instance.removeOutbox(item.id);
      } else {
        await AppDb.instance.updateOutbox(item.id, stillFailed, item.attempts + 1);
      }
    }
  }
}
