import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Loud alarm played on Android's alarm volume (works even when the ringer is
/// silent). The native side raises the alarm volume to maximum while it plays,
/// restores it afterwards, and stops on its own after five minutes.
class AlarmService {
  static const _ch = MethodChannel('safety/native');

  /// Sound id -> label shown in the app.
  static const sounds = <String, String>{
    'siren': 'Siren (rising wail)',
    'pulse': 'Pulse alarm (sharp beeps)',
  };

  static final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  static Future<void> start(String sound) async {
    if (!Platform.isAndroid) return;
    try {
      final ok = await _ch.invokeMethod<bool>('alarmStart', {'sound': sound}) ?? false;
      playing.value = ok;
    } on PlatformException catch (_) {
      playing.value = false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('alarmStop');
    } on PlatformException catch (_) {}
    playing.value = false;
  }
}
