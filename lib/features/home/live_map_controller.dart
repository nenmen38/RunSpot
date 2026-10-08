import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../run_history/run_history_controller.dart';

import 'data/live_runner_service.dart';
import 'data/location_service.dart';
import 'models/live_runner.dart';
import 'models/run_session.dart';

class LiveMapController extends ChangeNotifier {
  LiveMapController({
    required this.locationService,
    required this.runnerService,
    required this.runHistory,
  });

  final LocationService locationService;
  final LiveRunnerService runnerService;
  final RunHistoryController runHistory;
  LocationFix? position;
  List<LiveRunner> runners = [];
  LocationFailure? locationFailure;
  String? sharingError;
  String? runError;
  RunSession? runSession;
  bool startingRun = false;
  bool savingRun = false;
  bool locating = false;
  bool sharing = false;
  bool changingSharing = false;
  bool connected = false;
  int radiusMeters = 1000;
  bool _disposed = false;
  bool _active = true;
  bool _refreshing = false;
  int _generation = 0;
  DateTime? _lastPublished;
  Timer? _heartbeat;
  Timer? _refreshTimer;
  Timer? _runTimer;
  StreamSubscription<LocationFix>? _locations;
  Future<void> _writes = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || locating || !_active) return;
    locating = true;
    locationFailure = null;
    _notify();
    final generation = _generation;
    try {
      final fix = await locationService.current(requestPermission: true);
      if (_disposed || !_active || generation != _generation) return;
      _acceptPosition(fix);
      await _locations?.cancel();
      _locations = locationService.watch().listen(
        _acceptPosition,
        onError: (_) {
          unawaited(
            _locationLost(const LocationFailure(LocationProblem.unavailable)),
          );
        },
      );
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    } on LocationFailure catch (error) {
      if (!_disposed && generation == _generation) locationFailure = error;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        locationFailure = const LocationFailure(LocationProblem.unavailable);
      }
    } finally {
      if (!_disposed) {
        locating = false;
        _notify();
        if (_active && generation != _generation) unawaited(start());
      }
    }
  }

  void _acceptPosition(LocationFix fix) {
    if (_disposed || !_active) return;
    runSession?.accept(fix);
    if ((sharing || runSession?.isRunning == true) && !fix.isUsable) {
      unawaited(
        _locationLost(const LocationFailure(LocationProblem.unavailable)),
      );
      return;
    }
    position = fix;
    locationFailure = null;
    _notify();
    if (sharing && !changingSharing) unawaited(_publish());
  }

  Future<void> _tick() async {
    if (_disposed || !_active || locating) return;
    try {
      _acceptPosition(await locationService.current());
      if (sharing) await refresh();
    } on LocationFailure catch (error) {
      await _locationLost(error);
    } catch (_) {
      await _locationLost(const LocationFailure(LocationProblem.unavailable));
    }
  }

  Future<void> _locationLost(LocationFailure error) async {
    if (_disposed || !_active) return;
    pauseRun();
    locationFailure = error;
    position = null;
    if (sharing || changingSharing) await setSharing(false);
    _notify();
  }

  Future<void> startRun() async {
    if (_disposed ||
        !_active ||
        startingRun ||
        savingRun ||
        runSession?.isRunning == true ||
        runSession?.isFinished == true) {
      return;
    }
    startingRun = true;
    runError = null;
    _notify();
    try {
      final fix = await locationService.current(requestPermission: true);
      if (_disposed || !_active) return;
      if (!fix.isUsable) {
        runError = '정확한 현재 위치를 확인한 뒤 러닝을 시작해 주세요.';
        return;
      }
      if (_locations == null) await start();
      if (_disposed || !_active) return;
      if (_locations == null || locationFailure != null) {
        runError = locationFailure?.message ?? '위치 측정을 시작하지 못했습니다.';
        return;
      }
      _acceptPosition(fix);
      if (runSession == null) {
        runSession = RunSession(fix);
      } else {
        runSession!.resume(fix);
      }
      _runTimer?.cancel();
      _runTimer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    } on LocationFailure catch (error) {
      if (!_disposed) {
        runError = error.message;
        locationFailure = error;
      }
    } catch (_) {
      if (!_disposed) runError = '러닝을 시작하지 못했습니다. 다시 시도해 주세요.';
    } finally {
      if (!_disposed) {
        startingRun = false;
        _notify();
      }
    }
  }

  void pauseRun() {
    if (runSession == null) return;
    runSession!.pause();
    _runTimer?.cancel();
    _notify();
  }

  Future<RunSummary?> finishRun() async {
    final session = runSession;
    if (_disposed || session == null || savingRun) return null;
    final summary = session.finish();
    _runTimer?.cancel();
    runError = null;
    savingRun = true;
    _notify();
    try {
      if (sharing || changingSharing) await setSharing(false);
      await runHistory.save(summary);
      if (_disposed) return null;
      runSession = null;
      return summary;
    } catch (error) {
      if (!_disposed) {
        runError = '기록을 저장하지 못했습니다. ${RunHistoryController.message(error)}';
      }
      return null;
    } finally {
      if (!_disposed) {
        savingRun = false;
        _notify();
      }
    }
  }

  // 쓰기와 삭제를 직렬화하여 공유를 끈 뒤 늦은 업로드가 되살아나지 않게 합니다.
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> setSharing(bool value) async {
    if (_disposed || (value && (changingSharing || !_active))) return;
    final generation = ++_generation;
    changingSharing = true;
    sharingError = null;
    runners = [];
    sharing = false;
    connected = false;
    _refreshTimer?.cancel();
    _notify();
    try {
      await runnerService.disconnect();
      if (!value) {
        await _enqueue(runnerService.stopSharing);
        return;
      }
      final fix = position;
      if (fix == null || !fix.isUsable) {
        sharingError = '정확한 현재 위치를 확인한 뒤 공유할 수 있습니다.';
        return;
      }
      await _enqueue(() async {
        if (!_disposed && _active && generation == _generation) {
          await runnerService.publish(fix);
        }
      });
      if (_disposed || !_active || generation != _generation) return;
      sharing = true;
      _lastPublished = DateTime.now();
      await runnerService.connect(_scheduleRefresh, (value) {
        if (_disposed || !sharing || generation != _generation) return;
        connected = value;
        if (!value) runners = [];
        _notify();
        if (value) _scheduleRefresh();
      });
      await refresh();
    } catch (error) {
      if (!_disposed && generation == _generation) {
        sharing = false;
        sharingError = _message(error);
        try {
          await runnerService.disconnect();
        } catch (_) {
          // 채널 정리에 실패해도 위치 삭제 요청을 계속합니다.
        }
        try {
          await _enqueue(runnerService.stopSharing);
        } catch (_) {
          // 서버에서는 갱신되지 않은 위치가 2분 뒤 조회 대상에서 제외됩니다.
        }
      }
    } finally {
      if (!_disposed && generation == _generation) {
        changingSharing = false;
        _notify();
      }
    }
  }

  Future<void> _publish() async {
    final fix = position;
    final generation = _generation;
    if (fix == null ||
        !fix.isUsable ||
        (_lastPublished != null &&
            DateTime.now().difference(_lastPublished!) <
                const Duration(seconds: 5))) {
      return;
    }
    _lastPublished = DateTime.now();
    try {
      await _enqueue(() async {
        if (!_disposed && _active && sharing && generation == _generation) {
          await runnerService.publish(fix);
        }
      });
    } catch (error) {
      if (!_disposed && sharing && generation == _generation) {
        await setSharing(false);
        sharingError = _message(error);
        _notify();
      }
    }
  }

  void _scheduleRefresh() {
    if (_disposed || !sharing || _refreshTimer?.isActive == true) return;
    _refreshTimer = Timer(const Duration(seconds: 1), refresh);
  }

  Future<void> refresh() async {
    if (_disposed || !sharing || _refreshing || !_active) return;
    _refreshing = true;
    final generation = _generation;
    final radius = radiusMeters;
    try {
      final result = await runnerService.nearby(radius);
      if (!_disposed &&
          sharing &&
          generation == _generation &&
          radius == radiusMeters) {
        runners = result;
        sharingError = null;
        _notify();
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        runners = [];
        sharingError = _message(error);
        _notify();
      }
    } finally {
      _refreshing = false;
    }
  }

  void setRadius(int radius) {
    if (![500, 1000, 3000, 5000].contains(radius)) return;
    radiusMeters = radius;
    runners = [];
    _notify();
    _scheduleRefresh();
  }

  Future<void> setActive(bool active) async {
    if (_disposed || _active == active) return;
    _active = active;
    if (active) {
      await start();
    } else {
      pauseRun();
      _heartbeat?.cancel();
      await _locations?.cancel();
      _locations = null;
      await setSharing(false);
      position = null;
      _notify();
    }
  }

  String _message(Object error) {
    if (error is PostgrestException) {
      if (error.code == '42501') return error.message;
      if (error.code == 'PGRST202' || error.code == '42883') {
        return '서버의 실시간 위치 기능 설정이 필요합니다.';
      }
    }
    return '위치 공유 서버에 연결하지 못했습니다. 다시 시도해 주세요.';
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _heartbeat?.cancel();
    _refreshTimer?.cancel();
    _runTimer?.cancel();
    runSession?.pause();
    unawaited(_locations?.cancel());
    unawaited(runnerService.disconnect().catchError((Object _) {}));
    unawaited(_enqueue(runnerService.stopSharing).catchError((Object _) {}));
    super.dispose();
  }
}
