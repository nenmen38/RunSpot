import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../run_history/models/run_route.dart';
import '../../run_history/models/run_temperature.dart';

import 'live_runner.dart';
import 'run_pace.dart';

class RunSummary {
  const RunSummary({
    required this.clientRunId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.duration,
    this.route = const RunRoute.empty(),
    this.temperature,
  });
  final String clientRunId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final Duration duration;
  final RunRoute route;
  final RunTemperature? temperature;
}

class RunSession {
  RunSession(LocationFix start, {DateTime Function()? paceNow})
    : _pace = RunPace(now: paceNow) {
    _startSegment(start);
    _clock.start();
  }

  final _clock = Stopwatch();
  final _clientRunId = const Uuid().v4();
  final _startedAt = DateTime.now().toUtc();
  final RunPace _pace;
  final _segments = <List<LocationFix>>[];
  List<LocationFix>? _segment;
  List<List<LocationFix>>? _routeSnapshot;
  RunSummary? _summary;
  LocationFix? _previous;
  double _distanceMeters = 0;

  bool get isRunning => _clock.isRunning;
  bool get isFinished => _summary != null;
  Duration get duration => _clock.elapsed;
  double get distanceMeters => _distanceMeters;
  Duration? get currentPace => isRunning ? _pace.current : null;
  Duration? get averagePace => calculateRunPace(distanceMeters, duration);
  List<List<LocationFix>> get routeSegments =>
      _routeSnapshot ??= List<List<LocationFix>>.unmodifiable(
        _segments.map((segment) => List<LocationFix>.unmodifiable(segment)),
      );

  void _startSegment(LocationFix fix) {
    if (!fix.isUsable) {
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
  }

  void accept(LocationFix fix) {
    if (!isRunning) return;
    if (!fix.isUsable) {
      _previous = null;
      _segment = null;
      _pace.clear();
      return;
    }
    final previous = _previous;
    if (previous == null) {
      _startSegment(fix);
      return;
    }
    if (!fix.recordedAt.isAfter(previous.recordedAt)) return;
    // 위치가 끊긴 구간은 직선 거리로 추정해 더하지 않습니다.
    if (fix.recordedAt.difference(previous.recordedAt) >
        const Duration(seconds: 30)) {
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
    _previous = fix;
    _segment!.add(fix);
    _routeSnapshot = null;
    _pace.accept(_distanceMeters, fix.recordedAt);
  }

  void pause() {
    _clock.stop();
    _previous = null;
    _segment = null;
    _pace.clear();
  }

  void resume(LocationFix fix) {
    if (isFinished) return;
    _startSegment(fix);
    _clock.start();
  }

  RunSummary finish({RunTemperature? Function(DateTime)? temperatureAtEnd}) {
    pause();
    if (_summary != null) return _summary!;
    final endedAt = DateTime.now().toUtc();
    // 재시도에도 종료 시각과 당시 기온을 그대로 보존합니다.
    return _summary ??= RunSummary(
      clientRunId: _clientRunId,
      startedAt: _startedAt,
      endedAt: endedAt,
      temperature: temperatureAtEnd?.call(endedAt),
      distanceMeters: _distanceMeters,
      duration: duration,
      route: RunRoute(
        _segments.map(
          (segment) =>
              segment.map((fix) => LatLng(fix.latitude, fix.longitude)),
        ),
      ),
    );
  }
}
