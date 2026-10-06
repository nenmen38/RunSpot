import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import 'live_runner.dart';

class RunSummary {
  const RunSummary({required this.distanceMeters, required this.duration});
  final double distanceMeters;
  final Duration duration;
}

class RunSession {
  RunSession(LocationFix start) : _previous = start {
    _clock.start();
  }

  final _clock = Stopwatch();
  LocationFix? _previous;
  double _distanceMeters = 0;

  bool get isRunning => _clock.isRunning;
  Duration get duration => _clock.elapsed;
  double get distanceMeters => _distanceMeters;

  void accept(LocationFix fix) {
    if (!isRunning) return;
    if (!fix.isUsable) {
      _previous = null;
      return;
    }
    final previous = _previous;
    if (previous == null) {
      _previous = fix;
      return;
    }
    if (!fix.recordedAt.isAfter(previous.recordedAt)) return;
    // 위치가 끊긴 구간은 직선 거리로 추정해 더하지 않습니다.
    if (fix.recordedAt.difference(previous.recordedAt) >
        const Duration(seconds: 30)) {
      _previous = fix;
      return;
    }
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      fix.latitude,
      fix.longitude,
    );
    // GPS 오차 범위 안의 흔들림은 이동으로 누적하지 않습니다.
    if (distance < math.max(5, math.max(previous.accuracy, fix.accuracy))) {
      return;
    }
    _distanceMeters += distance;
    _previous = fix;
  }

  void pause() {
    _clock.stop();
    _previous = null;
  }

  void resume(LocationFix fix) {
    _previous = fix;
    _clock.start();
  }

  RunSummary finish() {
    pause();
    return RunSummary(distanceMeters: _distanceMeters, duration: duration);
  }
}
