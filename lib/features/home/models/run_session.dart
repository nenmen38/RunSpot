import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import 'live_runner.dart';

class RunSummary {
  const RunSummary({
    required this.clientRunId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.duration,
  });
  final String clientRunId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final Duration duration;
}

class RunSession {
  RunSession(LocationFix start) : _previous = start {
    _clock.start();
  }

  final _clock = Stopwatch();
  final _clientRunId = const Uuid().v4();
  final _startedAt = DateTime.now().toUtc();
  RunSummary? _summary;
  LocationFix? _previous;
  double _distanceMeters = 0;

  bool get isRunning => _clock.isRunning;
  bool get isFinished => _summary != null;
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
    if (isFinished) return;
    _previous = fix;
    _clock.start();
  }

  RunSummary finish() {
    pause();
    // 재시도할 때 동일한 식별자와 종료 시각을 사용해 중복 저장을 막습니다.
    return _summary ??= RunSummary(
      clientRunId: _clientRunId,
      startedAt: _startedAt,
      endedAt: DateTime.now().toUtc(),
      distanceMeters: _distanceMeters,
      duration: duration,
    );
  }
}
