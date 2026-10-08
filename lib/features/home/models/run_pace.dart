import 'dart:collection';

Duration? calculateRunPace(double distanceMeters, Duration duration) {
  if (!distanceMeters.isFinite ||
      distanceMeters <= 0 ||
      duration <= Duration.zero) {
    return null;
  }
  final seconds =
      duration.inMicroseconds /
      Duration.microsecondsPerSecond *
      1000 /
      distanceMeters;
  if (!seconds.isFinite || seconds < 1) return null;
  return Duration(seconds: seconds.round());
}

class RunPace {
  RunPace({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const window = Duration(seconds: 20);
  static const staleAfter = Duration(seconds: 15);
  final DateTime Function() _now;
  final _samples = Queue<_PaceSample>();
  DateTime? _lastMovementAt;

  void reset(double distanceMeters, DateTime recordedAt) {
    clear();
    _samples.add(_PaceSample(distanceMeters, recordedAt));
  }

  void clear() {
    _samples.clear();
    _lastMovementAt = null;
  }

  void accept(double distanceMeters, DateTime recordedAt) {
    if (_samples.isEmpty) {
      reset(distanceMeters, recordedAt);
      return;
    }
    final previous = _samples.last;
    if (!recordedAt.isAfter(previous.recordedAt) ||
        distanceMeters < previous.distanceMeters) {
      return;
    }
    if (distanceMeters > previous.distanceMeters) _lastMovementAt = recordedAt;
    _samples.add(_PaceSample(distanceMeters, recordedAt));
    final cutoff = recordedAt.subtract(window);
    // 구간 직전의 표본도 남겨 GPS 갱신 간격이 길어져도 계산 기준을 유지합니다.
    while (_samples.length > 2 &&
        !_samples.elementAt(1).recordedAt.isAfter(cutoff)) {
      _samples.removeFirst();
    }
  }

  Duration? get current {
    final lastMovement = _lastMovementAt;
    if (_samples.length < 2 || lastMovement == null) return null;
    final now = _now();
    if (now.difference(lastMovement).abs() > staleAfter ||
        now.difference(_samples.last.recordedAt).abs() > staleAfter) {
      return null;
    }
    final elapsed = _samples.last.recordedAt.difference(
      _samples.first.recordedAt,
    );
    final distance =
        _samples.last.distanceMeters - _samples.first.distanceMeters;
    // 시작 직후나 GPS 오차 수준의 이동에서는 불안정한 페이스를 표시하지 않습니다.
    if (elapsed < const Duration(seconds: 5) || distance < 10) return null;
    return calculateRunPace(distance, elapsed);
  }
}

class _PaceSample {
  const _PaceSample(this.distanceMeters, this.recordedAt);
  final double distanceMeters;
  final DateTime recordedAt;
}
