import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import 'live_runner.dart';

/// 시각·정확도를 보존하며 일시 정지와 위치 단절을 연결하지 않습니다.
class RunMotionTracker {
  RunMotionTracker({List<List<num>>? restored, this.notBefore}) {
    if (restored != null) {
      _samples.addAll(restored.map((point) => List<num>.of(point)));
      if (_samples.isNotEmpty) _segment = _samples.last[4].toInt() + 1;
    }
  }

  static const maximumAccuracy = 25.0;
  static const maximumGap = Duration(seconds: 10);
  final DateTime? notBefore;
  final _samples = <List<num>>[];
  LocationFix? _previous;
  List<num>? _latest;
  int _segment = 0;

  static bool usable(LocationFix fix) =>
      fix.isUsable &&
      fix.accuracy <= maximumAccuracy &&
      !fix.recordedAt.isAfter(DateTime.now().add(const Duration(seconds: 1)));

  static bool jumped(LocationFix previous, LocationFix next) {
    final seconds =
        next.recordedAt.difference(previous.recordedAt).inMicroseconds / 1e6;
    if (seconds <= 0) return false;
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      next.latitude,
      next.longitude,
    );
    return distance - previous.accuracy - next.accuracy > 35 * seconds;
  }

  void breakSegment() {
    _flush();
    _previous = null;
    _latest = null;
    _segment++;
  }

  void accept(LocationFix fix) {
    final earliest = notBefore;
    if (earliest != null && fix.recordedAt.isBefore(earliest)) return;
    if (!usable(fix)) {
      breakSegment();
      return;
    }
    final previous = _previous;
    if (previous != null) {
      if (!fix.recordedAt.isAfter(previous.recordedAt)) return;
      if (fix.recordedAt.difference(previous.recordedAt) > maximumGap ||
          jumped(previous, fix)) {
        breakSegment();
      }
    }
    final time = fix.recordedAt.millisecondsSinceEpoch;
    // 재개·복구 직후에도 과거 표본보다 시각이 앞서야 합니다.
    if (_samples.isNotEmpty && time <= _samples.last[0]) return;
    _previous = fix;
    _latest = [time, fix.latitude, fix.longitude, fix.accuracy, _segment];
    if (_samples.isEmpty || time - _samples.last[0] >= 5000) _flush();
  }

  void _flush() {
    final latest = _latest;
    if (latest != null && (_samples.isEmpty || latest[0] > _samples.last[0])) {
      _samples.add(latest);
    }
  }

  List<List<num>> snapshot() => List.unmodifiable([
    ..._samples.map((point) => List<num>.unmodifiable(point)),
    if (_latest != null && (_samples.isEmpty || _latest![0] > _samples.last[0]))
      List<num>.unmodifiable(_latest!),
  ]);

  static List<List<num>>? decode(Object? value) {
    if (value == null) return null;
    if (value is! List || value.length > 250000) {
      throw const FormatException('위치 측정값이 올바르지 않습니다.');
    }
    num lastTime = -1;
    num lastSegment = -1;
    return List.unmodifiable(
      value.map((item) {
        if (item is! List ||
            item.length != 5 ||
            item.any((v) => v is! num || !v.isFinite)) {
          throw const FormatException('위치 측정값이 올바르지 않습니다.');
        }
        final point = item.cast<num>();
        if (point[0] != point[0].round() ||
            point[0] <= lastTime ||
            point[1] < -90 ||
            point[1] > 90 ||
            point[2] < -180 ||
            point[2] > 180 ||
            point[3] < 0 ||
            point[3] > 100 ||
            point[4] < math.max(0, lastSegment) ||
            point[4] != point[4].round()) {
          throw const FormatException('위치 측정값의 범위가 올바르지 않습니다.');
        }
        lastTime = point[0];
        lastSegment = point[4];
        return List<num>.unmodifiable(point);
      }),
    );
  }
}
