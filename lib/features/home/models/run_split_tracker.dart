import '../../run_history/models/run_split.dart';

// GPS로 인정한 누적 거리와 일시 정지를 제외한 측정 시간만 사용합니다.
class RunSplitTracker {
  final _completed = <RunSplit>[];
  double _distance = 0;
  Duration _duration = Duration.zero;
  Duration _boundaryTime = Duration.zero;

  RunSplitTracker();
  RunSplitTracker.restore(
    List<RunSplit> splits,
    double distance,
    Duration duration,
  ) {
    _completed.addAll(splits.where((split) => split.distanceMeters == 1000));
    _boundaryTime = _completed.fold(
      Duration.zero,
      (sum, split) => sum + split.duration,
    );
    _distance = distance;
    _duration = duration;
  }

  void advance(double distance, Duration duration) {
    if (distance <= _distance || duration < _duration) return;
    var boundary = (_completed.length + 1) * 1000;
    while (boundary <= distance) {
      // GPS 표본 사이에서 1km를 통과한 시각은 거리 비율로 보간합니다.
      final fraction = (boundary - _distance) / (distance - _distance);
      final at =
          _duration +
          Duration(
            microseconds: ((duration - _duration).inMicroseconds * fraction)
                .round(),
          );
      _completed.add(
        RunSplit(distanceMeters: 1000, duration: at - _boundaryTime),
      );
      _boundaryTime = at;
      boundary += 1000;
    }
    _distance = distance;
    _duration = duration;
  }

  List<RunSplit> snapshot(double distance, Duration duration) {
    final result = [..._completed];
    final remaining = distance - _completed.length * 1000;
    if (remaining > 0) {
      result.add(
        RunSplit(distanceMeters: remaining, duration: duration - _boundaryTime),
      );
    } else if (result.isNotEmpty && duration > _boundaryTime) {
      // 정확히 1km에서 멈춘 뒤의 활동 시간도 마지막 구간에 포함합니다.
      final last = result.removeLast();
      result.add(
        RunSplit(
          distanceMeters: last.distanceMeters,
          duration: last.duration + duration - _boundaryTime,
        ),
      );
    }
    return List.unmodifiable(result);
  }
}
