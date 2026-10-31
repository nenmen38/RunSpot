import 'dart:math' as math;

import '../../run_history/models/run_analysis_data.dart';
import 'live_runner.dart';

/// 활동 시각·중단 사유·신뢰할 수 있는 고도 차이와 GPS 품질을 별도로 수집합니다.
class RunAnalysisTracker {
  RunAnalysisTracker(this.startedAt, {RunAnalysisData? restored}) {
    if (restored != null) {
      _windows.addAll(restored.windows);
      _pauses.addAll(restored.pauses);
      _elevation.addAll(restored.elevation);
      for (final row in restored.gps) {
        _gps[row[0].toInt()] = List<num>.of(row);
      }
    }
  }
  final DateTime startedAt;
  final _windows = <List<num>>[],
      _pauses = <List<num>>[],
      _elevation = <List<num>>[];
  final _gps = <int, List<num>>{};
  int? _windowStart, _pauseStart;
  int _activeStart = 0, _reason = 0;
  LocationFix? _anchor;
  DateTime? _lastAltitudeFixTime;
  double _anchorDistance = 0;
  DateTime? _lastFix;
  int _offset(DateTime time) =>
      math.max(0, time.difference(startedAt).inMilliseconds);

  void resume(DateTime time, Duration active) {
    final offset = _offset(time);
    if (_pauseStart != null) _pauses.add([_pauseStart!, offset, _reason]);
    _pauseStart = null;
    _windowStart = offset;
    _activeStart = active.inMilliseconds;
    breakElevation();
    _lastFix = null;
  }

  void restorePause(DateTime checkpointTime) {
    _pauseStart = _offset(checkpointTime);
    _reason = 2;
  }

  void pause(DateTime time, Duration active, int reason) {
    if (_windowStart == null) return;
    _windows.add([
      _windowStart!,
      _offset(time),
      _activeStart,
      active.inMilliseconds,
    ]);
    _windowStart = null;
    _pauseStart = reason == 4 ? null : _offset(time);
    _reason = reason;
    breakElevation();
    _lastFix = null;
  }

  void breakElevation() {
    _anchor = null;
    _lastAltitudeFixTime = null;
  }

  void observe(LocationFix fix, double distance, {required bool accepted}) {
    if (_lastFix != null && !fix.recordedAt.isAfter(_lastFix!)) return;
    final index = math.min(1001, distance ~/ 1000 + 1);
    final row = _gps.putIfAbsent(index, () => [index, 0, 0, 0, 0, 0, 0, 0]);
    row[1] += 1;
    if (!accepted) row[2] += 1;
    if (fix.accuracy.isFinite && fix.accuracy >= 0 && fix.accuracy <= 1000000) {
      row[7] += 1;
      row[5] += fix.accuracy;
      row[6] = math.max(row[6], fix.accuracy);
    }
    if (fix.recordedAt.isBefore(startedAt) ||
        fix.recordedAt.isAfter(
          DateTime.now().add(const Duration(seconds: 1)),
        )) {
      breakElevation();
      return;
    }
    if (_lastFix != null) {
      final gap = fix.recordedAt.difference(_lastFix!).inMilliseconds;
      if (gap > 10000) {
        row[3] += 1;
        row[4] += gap;
        breakElevation();
      }
    }
    if (!fix.recordedAt.isAfter(
          DateTime.now().add(const Duration(seconds: 1)),
        ) &&
        !fix.recordedAt.isBefore(startedAt)) {
      _lastFix = fix.recordedAt;
    }
    if (!accepted) breakElevation();
  }

  void altitude(LocationFix fix, double distance) {
    final previousTime = _lastAltitudeFixTime;
    if (previousTime != null &&
        fix.recordedAt.difference(previousTime) > const Duration(seconds: 10)) {
      breakElevation();
    }
    _lastAltitudeFixTime = fix.recordedAt;
    final height = fix.altitude, error = fix.altitudeAccuracy;
    if (height == null ||
        error == null ||
        !height.isFinite ||
        !error.isFinite ||
        error <= 0 ||
        error > 10 ||
        height.abs() > 10000) {
      breakElevation();
      return;
    }
    final anchor = _anchor;
    if (anchor != null && distance > _anchorDistance) {
      final delta = height - anchor.altitude!;
      final uncertainty = error + anchor.altitudeAccuracy!;
      // 오차보다 작은 고도 흔들림은 누적하지 않고 100m 간격에서 관측 차이를 보존합니다.
      if (delta.abs() > math.max(3, uncertainty) ||
          distance - _anchorDistance >= 100) {
        _elevation.add([_anchorDistance, distance, delta, uncertainty]);
        _anchor = fix;
        _anchorDistance = distance;
      }
    } else {
      _anchor = fix;
      _anchorDistance = distance;
    }
  }

  RunAnalysisData snapshot(DateTime time, Duration active) =>
      RunAnalysisData.decode({
        'version': 1,
        'windows': [
          ..._windows,
          if (_windowStart != null)
            [_windowStart!, _offset(time), _activeStart, active.inMilliseconds],
        ],
        'pauses': [
          ..._pauses,
          if (_pauseStart != null) [_pauseStart!, _offset(time), _reason],
        ],
        'elevation': _elevation,
        'gps': _gps.values.toList(),
      })!;
}
