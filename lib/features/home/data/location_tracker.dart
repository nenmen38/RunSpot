import 'dart:async';

import '../models/live_runner.dart';
import 'location_service.dart';

enum LocationTrackingMode { stopped, map, recording }

class LocationTracker {
  LocationTracker(this.service, {required this.onFix, required this.onFailure});

  final LocationService service;
  final void Function(LocationFix) onFix;
  final void Function(LocationFailure) onFailure;
  LocationTrackingMode _desired = LocationTrackingMode.stopped;
  LocationTrackingMode _mode = LocationTrackingMode.stopped;
  StreamSubscription<LocationFix>? _subscription;
  Completer<LocationFix?>? _ready;
  Future<void> _changes = Future.value();
  bool _closed = false;
  int _streamId = 0;

  bool get isRecording => _mode == LocationTrackingMode.recording;

  Future<LocationFix?> setMode(
    LocationTrackingMode mode, {
    bool waitForFix = false,
  }) async {
    if (_closed) return null;
    _desired = mode;
    final change = _enqueue();
    await change;
    if (_closed || _mode != mode || _desired != mode || !waitForFix) {
      return null;
    }
    // 첫 GPS 응답 전에는 백그라운드 측정이 준비된 것으로 간주하지 않습니다.
    return _ready?.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw const LocationFailure(LocationProblem.unavailable),
    );
  }

  Future<void> _enqueue() {
    final change = _changes.then((_) => _reconcile());
    _changes = change.catchError((Object _) {});
    return change;
  }

  Future<void> _reconcile() async {
    if (_mode == _desired && !_closed) return;
    ++_streamId;
    if (_ready?.isCompleted == false) _ready!.complete(null);
    final previous = _subscription;
    _subscription = null;
    _mode = LocationTrackingMode.stopped;
    // 플러그인의 기존 스트림을 완전히 해제해야 새 실행 설정이 적용됩니다.
    await previous?.cancel();
    if (_closed || _desired == LocationTrackingMode.stopped) return;
    final mode = _desired;
    final streamId = ++_streamId;
    final ready = _ready = Completer<LocationFix?>();
    _mode = mode;
    try {
      _subscription = service
          .watch(recording: isRecording)
          .listen(
            (fix) {
              if (_closed || streamId != _streamId) return;
              if (!ready.isCompleted) ready.complete(fix);
              onFix(fix);
            },
            onError: (Object error) => _failed(streamId, error),
            onDone: () => _failed(
              streamId,
              const LocationFailure(LocationProblem.unavailable),
            ),
          );
    } catch (_) {
      _mode = LocationTrackingMode.stopped;
      if (!ready.isCompleted) ready.complete(null);
      rethrow;
    }
  }

  void _failed(int streamId, Object error) {
    if (_closed || streamId != _streamId) return;
    ++_streamId;
    if (_ready?.isCompleted == false) _ready!.complete(null);
    _desired = LocationTrackingMode.stopped;
    onFailure(
      error is LocationFailure
          ? error
          : const LocationFailure(LocationProblem.unavailable),
    );
    unawaited(_enqueue().catchError((Object _) {}));
  }

  Future<void> close() {
    _closed = true;
    _desired = LocationTrackingMode.stopped;
    ++_streamId;
    if (_ready?.isCompleted == false) _ready!.complete(null);
    return _enqueue();
  }
}
