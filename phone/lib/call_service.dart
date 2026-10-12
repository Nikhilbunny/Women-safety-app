import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'alarm_service.dart';
import 'models.dart';

/// Places phone calls to your emergency contacts.
///
/// A phone can only hold one call at a time, so "call all" works as a chain:
/// it calls the first contact, and when you come back to the app after the
/// call it asks whether to call the next one.
class CallService with WidgetsBindingObserver {
  CallService._();
  static final CallService instance = CallService._();

  /// Lets this service show a dialog from anywhere in the app.
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static const _ch = MethodChannel('safety/native');

  List<Contact> _chain = [];
  int _idx = -1;
  bool _awaitingReturn = false;
  bool _sawPause = false;

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  /// Asks for the call permission. Without it Android only opens the dialer
  /// with the number filled in, and you press the green button yourself.
  Future<void> _ensurePermission() async {
    if (Platform.isAndroid) {
      await Permission.phone.request();
    }
  }

  Future<void> _dial(String number) async {
    await AlarmService.stop(); // you need to hear the call
    if (Platform.isAndroid) {
      try {
        await _ch.invokeMethod('callNumber', {'number': number});
        return;
      } on PlatformException catch (_) {}
    }
    await launchUrl(Uri(scheme: 'tel', path: number));
  }

  /// Calls one contact.
  Future<void> callOne(Contact c) async {
    _awaitingReturn = false;
    _idx = -1;
    await _ensurePermission();
    await _dial(c.phone);
  }

  /// Calls the first contact, then offers the next one after each call ends.
  Future<void> startChain(List<Contact> contacts) async {
    if (contacts.isEmpty) return;
    _chain = List<Contact>.from(contacts);
    _idx = 0;
    await _ensurePermission();
    await _dialCurrent();
  }

  Future<void> _dialCurrent() async {
    _awaitingReturn = true;
    _sawPause = false;
    await _dial(_chain[_idx].phone);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_awaitingReturn) return;
    if (state == AppLifecycleState.paused) {
      _sawPause = true; // the dialer took over
    } else if (state == AppLifecycleState.resumed && _sawPause) {
      _awaitingReturn = false;
      _sawPause = false;
      _askNext();
    }
  }

  Future<void> _askNext() async {
    final next = _idx + 1;
    if (next >= _chain.length) {
      _idx = -1;
      return;
    }
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final c = _chain[next];
    final who = c.relation.isEmpty ? c.name : '${c.name} (${c.relation})';
    final go = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (d) => AlertDialog(
        title: const Text('Call ended'),
        content: Text('Call $who next?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Stop')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Call next')),
        ],
      ),
    );
    if (go == true) {
      _idx = next;
      await _dialCurrent();
    } else {
      _idx = -1;
    }
  }
}
