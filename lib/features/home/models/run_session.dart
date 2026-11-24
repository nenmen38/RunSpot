import '../../run_history/models/run_analysis_data.dart';
import 'run_analysis_tracker.dart';

import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../run_history/models/run_route.dart';
import '../../run_history/models/run_temperature.dart';

import 'live_runner.dart';
import 'run_pace.dart';
import 'run_split_tracker.dart';
import 'run_motion_tracker.dart';
import '../../run_history/models/run_split.dart';

class RunSummary {
  const RunSummary({
    required this.clientRunId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.duration,
    this.route = const RunRoute.empty(),
    this.temperature,
    this.splits,
    this.motionSamples,
    this.analysisData,
  });
  static const minimumRecordDistanceMeters = 300;

  bool get canSaveRecord =>
      distanceMeters.isFinite &&
      distanceMeters >= minimumRecordDistanceMeters &&
      endedAt.isAfter(startedAt);

  final String clientRunId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final Duration duration;
  final RunRoute route;
  final RunTemperature? temperature;
  final List<RunSplit>? splits;
  final List<List<num>>? motionSamples;
  final RunAnalysisData? analysisData;
}

class RunSession {
  RunSession(
    LocationFix start, {
    DateTime Function()? paceNow,
    DateTime Function()? now,
    this.autoPauseEnabled,
  }) : _pace = RunPace(now: paceNow),
       _now = now ?? DateTime.now,
       _clientRunId = const Uuid().v4(),
       _startedAt = (now ?? DateTime.now)().toUtc() {
    _analysis = RunAnalysisTracker(_startedAt)
      ..resume(_startedAt, Duration.zero);
    _splits = RunSplitTracker();
    _motion = RunMotionTracker(notBefore: _startedAt);
    _startSegment(start);
    _clock.start();
  }

  /// 자동 일시정지를 쓸지 매번 확인합니다. 없으면 쓰지 않습니다.
  bool Function()? autoPauseEnabled;

  /// 이 시간 동안 움직이지 않으면 자동으로 일시정지합니다.
  static const autoPauseAfter = Duration(seconds: 10);

  /// 이만큼 넘게 움직여야 '움직였다'고 봅니다(GPS 흔들림 제외).
  static const autoPauseMoveMeters = 10.0;

  /// 자동 일시정지 뒤 이보다 멀리 떨어진 위치는 차량 이동 등으로 보고 선을 잇지 않습니다.
  static const autoResumeMaxJumpMeters = 300.0;

  final DateTime Function() _now;
  bool _autoPaused = false;
  LocationFix? _stillAnchor;
  DateTime? _lastMovedAt;

  RunAnalysisTracker? _analysis;
  RunSplitTracker? _splits;
  RunMotionTracker? _motion = RunMotionTracker();
  final _clock = Stopwatch();
  final String _clientRunId;
  final DateTime _startedAt;
  Duration _restoredDuration = Duration.zero;
  final RunPace _pace;
  final _segments = <List<LocationFix>>[];
  List<LocationFix>? _segment;
  List<List<LocationFix>>? _routeSnapshot;
  RunSummary? _summary;
  LocationFix? _previous;
  double _distanceMeters = 0;

  /// 러닝 중인지입니다. 자동 일시정지 중에도 측정(위치 기록·공유)은 계속하므로 true입니다.
  bool get isRunning => _clock.isRunning || _autoPaused;

  /// 멈춰 있어서 시간 측정을 잠시 멈춘 상태입니다. 다시 달리면 같은 경로로 이어집니다.
  bool get isAutoPaused => _autoPaused;
  String get clientRunId => _clientRunId;
  bool get isFinished => _summary != null;
  Duration get duration => _restoredDuration + _clock.elapsed;
  double get distanceMeters => _distanceMeters;
  Duration? get currentPace => _clock.isRunning ? _pace.current : null;
  Duration? get averagePace => calculateRunPace(distanceMeters, duration);

  /// 다 달린 1km 구간입니다. 1km마다 음성 안내에 씁니다.
  List<RunSplit> get completedSplits => _splits?.completed ?? const [];
  List<List<LocationFix>> get routeSegments =>
      _routeSnapshot ??= List<List<LocationFix>>.unmodifiable(
        _segments.map((segment) => List<LocationFix>.unmodifiable(segment)),
      );

  RunSession.restore(
    RunSummary checkpoint, {
    bool finished = false,
    this.autoPauseEnabled,
  }) : _pace = RunPace(),
       _now = DateTime.now,
       _clientRunId = checkpoint.clientRunId,
       _startedAt = checkpoint.startedAt {
    _motion = checkpoint.motionSamples == null
        ? null
        : RunMotionTracker(
            restored: checkpoint.motionSamples,
            notBefore: _startedAt,
          );
    if (checkpoint.analysisData != null) {
      _analysis = RunAnalysisTracker(
        _startedAt,
        restored: checkpoint.analysisData,
      );
      if (!finished) _analysis!.restorePause(checkpoint.endedAt);
    }
    _restoredDuration = checkpoint.duration;
    _distanceMeters = checkpoint.distanceMeters;
    if (checkpoint.splits != null) {
      _splits = RunSplitTracker.restore(
        checkpoint.splits!,
        checkpoint.distanceMeters,
        checkpoint.duration,
      );
    }
    _summary = finished ? checkpoint : null;
    for (final segment in checkpoint.route.segments) {
      _segments.add(
        segment
            .map(
              (point) => LocationFix(
                latitude: point.latitude,
                longitude: point.longitude,
                accuracy: 0,
                recordedAt: checkpoint.endedAt,
              ),
            )
            .toList(),
      );
    }
    // 복구된 경로는 표시만 하고 재개 시 새 구간으로 측정합니다.
  }

  RunSummary checkpoint() {
    if (_summary != null) return _summary!;
    final measuredDuration = duration;
    final checkpointTime = DateTime.now().toUtc();
    return RunSummary(
      clientRunId: _clientRunId,
      startedAt: _startedAt,
      endedAt: checkpointTime,
      distanceMeters: distanceMeters,
      duration: measuredDuration,
      analysisData: _analysis?.snapshot(checkpointTime, measuredDuration),
      motionSamples: _motion?.snapshot(),
      splits: _splits?.snapshot(distanceMeters, measuredDuration),
      route: RunRoute(
        _segments.map(
          (segment) =>
              segment.map((fix) => LatLng(fix.latitude, fix.longitude)),
        ),
      ),
    );
  }

  void _startSegment(LocationFix fix) {
    _analysis?.breakElevation();
    _analysis?.altitude(fix, _distanceMeters);
    _motion?.breakSegment();
    _motion?.accept(fix);
    if (!RunMotionTracker.usable(fix)) {
      _previous = null;
      _segment = null;
      _pace.clear();
      return;
    }
    _previous = fix;
    _segment = [fix];
    _segments.add(_segment!);
    _routeSnapshot = null;
    _pace.reset(_distanceMeters, fix.recordedAt);
    _markMoved(fix);
  }

  void _markMoved(LocationFix fix) {
    _stillAnchor = fix;
    _lastMovedAt = fix.recordedAt;
  }

  bool get _autoPauseOn => autoPauseEnabled?.call() == true;

  /// 1초마다 불립니다. 위치가 오지 않아도 멈춘 지 10초가 지나면 자동 일시정지합니다.
  void tick() {
    if (!_clock.isRunning || _autoPaused || !_autoPauseOn) return;
    final moved = _lastMovedAt;
    if (moved != null && _now().toUtc().difference(moved) >= autoPauseAfter) {
      _autoPause();
    }
  }

  /// 시간만 멈춥니다. 경로(마지막 위치와 현재 구간)는 그대로 두어 다시 달리면 선이 이어집니다.
  void _autoPause() {
    _clock.stop();
    _autoPaused = true;
    _analysis?.pause(_now().toUtc(), duration, 0);
    _pace.clear();
  }

  /// 다시 움직이면 시간을 이어서 재고, 멈췄던 자리에서 새 위치까지 같은 선으로 잇습니다.
  void _autoResume(LocationFix fix) {
    _autoPaused = false;
    _analysis?.resume(_now().toUtc(), duration);
    _clock.start();
    final previous = _previous;
    if (previous == null || _segment == null) {
      _startSegment(fix);
      return;
    }
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      fix.latitude,
      fix.longitude,
    );
    if (distance > autoResumeMaxJumpMeters + previous.accuracy + fix.accuracy) {
      // 멈춘 사이 차량 등으로 멀리 옮겨졌으면 그 사이 거리는 넣지 않고 새로 그립니다.
      _startSegment(fix);
      return;
    }
    _distanceMeters += distance;
    _analysis?.altitude(fix, _distanceMeters);
    _splits?.advance(_distanceMeters, duration);
    _previous = fix;
    _segment!.add(fix);
    _routeSnapshot = null;
    _pace.reset(_distanceMeters, fix.recordedAt);
    _markMoved(fix);
  }

  void accept(LocationFix fix) {
    if (!isRunning) return;
    if (_autoPaused) {
      // 자동 일시정지 중에는 거리·경로를 늘리지 않고, 확실히 움직였을 때만 다시 시작합니다.
      if (!RunMotionTracker.usable(fix)) return;
      final anchor = _previous ?? _stillAnchor;
      if (anchor == null) {
        _autoResume(fix);
        return;
      }
      final moved = Geolocator.distanceBetween(
        anchor.latitude,
        anchor.longitude,
        fix.latitude,
        fix.longitude,
      );
      if (moved > math.max(autoPauseMoveMeters * 1.5, fix.accuracy)) {
        _autoResume(fix);
      }
      return;
    }
    _analysis?.observe(
      fix,
      _distanceMeters,
      accepted:
          RunMotionTracker.usable(fix) &&
          (_previous == null || !RunMotionTracker.jumped(_previous!, fix)),
    );
    _motion?.accept(fix);
    if (!RunMotionTracker.usable(fix)) {
      // 건물·나무 사이에서 잠깐 부정확한 위치가 와도 경로는 끊지 않고 그 위치만 버립니다.
      _pace.clear();
      return;
    }
    // 멈춰 있는지 확인합니다. 기준점에서 일정 거리 넘게 벗어나면 움직인 것으로 봅니다.
    final anchor = _stillAnchor;
    if (anchor == null ||
        Geolocator.distanceBetween(
              anchor.latitude,
              anchor.longitude,
              fix.latitude,
              fix.longitude,
            ) >
            math.max(autoPauseMoveMeters, fix.accuracy)) {
      _markMoved(fix);
    } else if (_autoPauseOn &&
        fix.recordedAt.difference(_lastMovedAt!) >= autoPauseAfter) {
      // 화면이 꺼져 1초 확인이 멈춰도, 위치가 올 때마다 멈춘 지 10초가 지났는지 봅니다.
      _autoPause();
      return;
    }
    final previous = _previous;
    if (previous == null) {
      _startSegment(fix);
      return;
    }
    if (!fix.recordedAt.isAfter(previous.recordedAt)) return;
    // 잠깐 위치가 끊겨도 달릴 수 있는 속도로 이어지면 같은 경로로 잇습니다.
    // 너무 오래 끊겼거나 순간 이동한 위치는 새 구간으로 시작하고 거리를 추정하지 않습니다.
    if (!continuesRoute(previous, fix)) {
      _startSegment(fix);
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
      _pace.accept(_distanceMeters, fix.recordedAt);
      return;
    }
    _distanceMeters += distance;
    _analysis?.altitude(fix, _distanceMeters);
    _splits?.advance(_distanceMeters, duration);
    _previous = fix;
    _segment!.add(fix);
    _routeSnapshot = null;
    _pace.accept(_distanceMeters, fix.recordedAt);
  }

  /// 경로를 이어 그릴 수 있는 가장 긴 위치 끊김입니다.
  static const maximumRouteGap = Duration(seconds: 60);

  /// 위치가 잠깐 끊긴 동안의 평균 속도 상한(m/s)입니다. 전력 질주보다 조금 빠릅니다.
  static const maximumGapSpeed = 8.0;

  static bool continuesRoute(LocationFix previous, LocationFix next) {
    final gap = next.recordedAt.difference(previous.recordedAt);
    if (gap <= RunMotionTracker.maximumGap) {
      return !RunMotionTracker.jumped(previous, next);
    }
    if (gap > maximumRouteGap) return false;
    final distance = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      next.latitude,
      next.longitude,
    );
    final seconds = gap.inMicroseconds / Duration.microsecondsPerSecond;
    return distance - previous.accuracy - next.accuracy <=
        maximumGapSpeed * seconds;
  }

  void pause({int reason = 0}) {
    _motion?.breakSegment();
    final wasAutoPaused = _autoPaused;
    _autoPaused = false;
    _clock.stop();
    // 자동 일시정지로 이미 멈춘 시간 구간은 다시 닫지 않습니다.
    if (!wasAutoPaused || reason == 4) {
      _analysis?.pause(DateTime.now().toUtc(), duration, reason);
    }
    _previous = null;
    _segment = null;
    _pace.clear();
  }

  void resume(LocationFix fix) {
    if (isFinished) return;
    // 자동 일시정지 중에 '다시 시작'을 눌러도 같은 경로로 이어갑니다.
    if (_autoPaused) {
      _autoResume(fix);
      return;
    }
    if (isRunning) return;
    _analysis?.resume(DateTime.now().toUtc(), duration);
    _startSegment(fix);
    _clock.start();
  }

  RunSummary finish({RunTemperature? Function(DateTime)? temperatureAtEnd}) {
    pause(reason: 4);
    if (_summary != null) return _summary!;
    final endedAt = DateTime.now().toUtc();
    // 재시도에도 종료 시각과 당시 기온을 그대로 보존합니다.
    return _summary ??= RunSummary(
      clientRunId: _clientRunId,
      startedAt: _startedAt,
      endedAt: endedAt,
      temperature: temperatureAtEnd?.call(endedAt),
      analysisData: _analysis?.snapshot(endedAt, duration),
      distanceMeters: _distanceMeters,
      duration: duration,
      motionSamples: _motion?.snapshot(),
      splits: _splits?.snapshot(distanceMeters, duration),
      route: RunRoute(
        _segments.map(
          (segment) =>
              segment.map((fix) => LatLng(fix.latitude, fix.longitude)),
        ),
      ),
    );
  }
}
