import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// Fires [onShake] after three hard shakes within ~1.5 seconds.
/// Runs on the accelerometer only, so it needs no internet. It works while
/// the app is in the foreground; OS background limits apply otherwise.
class ShakeDetector {
  ShakeDetector({required this.onShake});

  final void Function() onShake;
  StreamSubscription<AccelerometerEvent>? _sub;
  final List<DateTime> _hits = [];

  static const double _thresholdG = 2.7;
  static const Duration _window = Duration(milliseconds: 1500);

  void start() {
    _sub ??= accelerometerEventStream().listen((e) {
      final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 9.81;
      if (g < _thresholdG) return;
      final now = DateTime.now();
      if (_hits.isNotEmpty && now.difference(_hits.last).inMilliseconds < 200) return; // debounce
      _hits.add(now);
      _hits.removeWhere((t) => now.difference(t) > _window);
      if (_hits.length >= 3) {
        _hits.clear();
        onShake();
      }
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _hits.clear();
  }
}
