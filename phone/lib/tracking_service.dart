import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Dart side of the Android foreground service that records your location,
/// texts it to your contacts every few minutes, and sends a last alert when
/// the battery is almost empty or the phone starts shutting down.
class TrackingService {
  static const _ch = MethodChannel('safety/native');

  static bool get supported => Platform.isAndroid;

  static Future<bool> isOn() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('trackingState') ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  static Future<void> start(int minutes) async {
    await _ch.invokeMethod('startTracking', {'minutes': minutes});
  }

  static Future<void> stop() async {
    await _ch.invokeMethod('stopTracking');
  }

  /// Recorded points, oldest first, as [lat, lng].
  static Future<List<List<double>>> trail() async {
    if (!supported) return const [];
    try {
      final raw = await _ch.invokeMethod<String>('getTrail');
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
          .toList();
    } on PlatformException catch (_) {
      return const [];
    }
  }
}
