import 'dart:async';

import '../diagnostics/error_reporter.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../run_history/run_history_controller.dart';
import '../run_history/models/run_temperature.dart';
import '../profile/data/run_sharing_preference_service.dart';

import 'data/live_runner_service.dart';
import 'data/location_service.dart';
import 'data/location_tracker.dart';
import 'data/run_checkpoint_store.dart';
import 'models/live_runner.dart';
import 'models/run_session.dart';

class LiveMapController extends ChangeNotifier {
  LiveMapController({
    required this.locationService,
    required this.runnerService,
    required this.runHistory,
    this.sharingPreferenceService,
    this.checkpointStore,
  });

  final LocationService locationService;
  final LiveRunnerService runnerService;
  final RunHistoryController runHistory;
  final RunCheckpointStore? checkpointStore;
  Future<void>? _restoring;
  bool _recoveryLoaded = false;
  bool recoveredRun = false;
  Timer? _checkpointTimer;
  Future<void> _checkpointWrites = Future.value();

  Future<void> restoreRun() =>
      _restoring ??= _restoreRun().whenComplete(() => _restoring = null);

  Future<void> _restoreRun() async {
    if (_recoveryLoaded || checkpointStore == null) {
      _recoveryLoaded = true;
      return;
    }
    if (!runHistory.service.isCurrentOwner) return;
    try {
      final checkpoint = await checkpointStore!.load();
      if (_disposed || !runHistory.service.isCurrentOwner) return;
      if (checkpoint != null && runSession == null) {
        runSession = RunSession.restore(
          checkpoint.summary,
          finished: checkpoint.finished,
        );
        recoveredRun = true;
      }
      _recoveryLoaded = true;
    } catch (_) {
      runError = '진행 중 러닝을 복구하지 못했습니다. 다시 시도해 주세요.';
    }
    _notify();
  }

  Future<void> _saveCheckpoint() async {
    final session = runSession;
    if (checkpointStore == null ||
        session == null ||
        _disposed ||
        !runHistory.service.isCurrentOwner) {
      return;
    }
    final checkpoint = RunCheckpoint(
      session.checkpoint(),
      finished: session.isFinished,
    );
    final write = _checkpointWrites.then(
      (_) => checkpointStore!.save(checkpoint),
    );
    _checkpointWrites = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      if (!_disposed) {
        runError = '진행 중 러닝을 기기에 보관하지 못했습니다. 저장 공간을 확인해 주세요.';
        _notify();
      }
    }
  }

  final RunSharingPreferenceService? sharingPreferenceService;
  bool shareWhileRunning = false;
  bool loadingSharingPreference = false;
  bool savingSharingPreference = false;
  String? sharingPreferenceError;
  bool _preferenceLoaded = false;
  bool? _unsavedPreference;
  int _preferenceGeneration = 0;

  bool get sharingPreferenceLoaded =>
      sharingPreferenceService == null || _preferenceLoaded;
  LocationFix? position;
  List<LiveRunner> runners = [];
  int _runnerRevision = 0;
  LocationFailure? locationFailure;
  String? sharingError;
  String? runError;
  RunSession? runSession;
  bool startingRun = false;
  bool groupPreparing = false;
  bool groupPrepared = false;

  Future<bool> prepareGroupRun() async {
    await restoreRun();
    if (_disposed ||
        !_active ||
        !_recoveryLoaded ||
        runSession != null ||
        startingRun ||
        groupPreparing) {
      return false;
    }
    groupPreparing = true;
    final generation = ++_activityGeneration;
    try {
      final fix = await locationService.current(requestPermission: true);
      if (_disposed ||
          !_active ||
          generation != _activityGeneration ||
          !fix.isUsable) {
        return false;
      }
      locationFailure = null;
      final ready = await _tracker.setMode(
        LocationTrackingMode.recording,
        waitForFix: true,
      );
      if (_disposed ||
          !_active ||
          generation != _activityGeneration ||
          ready?.isUsable != true ||
          runSession != null) {
        return false;
      }
      position = ready;
      groupPrepared = true;
      return true;
    } catch (_) {
      return false;
    } finally {
      groupPreparing = false;
      if (!groupPrepared) unawaited(_syncTracking());
      _notify();
    }
  }

  Future<void> cancelGroupPreparation() async {
    if (groupPrepared || groupPreparing) _activityGeneration++;
    groupPreparing = false;
    groupPrepared = false;
    if (!_disposed) await _syncTracking();
    _notify();
  }

  Future<String?> startPreparedGroupRun() async {
    final fix = position;
    if (_disposed ||
        !_active ||
        !groupPrepared ||
        runSession != null ||
        fix?.isUsable != true ||
        locationFailure != null ||
        !runHistory.service.isCurrentOwner) {
      return null;
    }
    groupPrepared = false;
    runSession = RunSession(fix!);
    final clientRunId = runSession!.clientRunId;
    _startTimers();
    await _saveCheckpoint();
    if (!_disposed && checkpointStore != null) {
      _checkpointTimer ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_saveCheckpoint()),
      );
    }
    _notify();
    if (shareWhileRunning) unawaited(_applySharingPreference());
    return clientRunId;
  }

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
  int _activityGeneration = 0;
  int? _runStartGeneration;
  DateTime? _lastPublished;
  Timer? _heartbeat;
  Timer? _refreshTimer;
  Timer? _runTimer;
  late final _tracker = LocationTracker(
    locationService,
    onFix: _acceptPosition,
    onFailure: (error) => unawaited(_locationLost(error)),
  );
  Future<void> _writes = Future.value();

  bool get canShareLocation =>
      !_disposed &&
      _active &&
      !startingRun &&
      !savingRun &&
      (sharingPreferenceService == null ||
          (sharingPreferenceLoaded &&
              shareWhileRunning &&
              sharingPreferenceService!.isCurrentOwner)) &&
      runSession?.isRunning == true &&
      locationFailure == null &&
      position?.isUsable == true;

  Future<void> loadSharingPreference() async {
    final service = sharingPreferenceService;
    if (_disposed ||
        service == null ||
        loadingSharingPreference ||
        savingSharingPreference) {
      return;
    }
    final generation = ++_preferenceGeneration;
    loadingSharingPreference = true;
    sharingPreferenceError = null;
    _notify();
    try {
      final enabled = await service.load().timeout(const Duration(seconds: 15));
      if (_disposed || generation != _preferenceGeneration) return;
      if (!service.isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
      shareWhileRunning = enabled;
      _preferenceLoaded = true;
    } catch (_) {
      if (_disposed || generation != _preferenceGeneration) return;
      shareWhileRunning = false;
      _preferenceLoaded = false;
      sharingPreferenceError = '위치 공유 설정을 불러오지 못했습니다. 공유는 꺼진 상태로 유지합니다.';
    } finally {
      if (!_disposed && generation == _preferenceGeneration) {
        loadingSharingPreference = false;
        _notify();
        unawaited(_applySharingPreference());
      }
    }
  }

  Future<void> setShareWhileRunning(bool enabled) async {
    if (_disposed ||
        loadingSharingPreference ||
        savingSharingPreference ||
        !sharingPreferenceLoaded) {
      return;
    }
    final generation = ++_preferenceGeneration;
    savingSharingPreference = true;
    sharingPreferenceError = null;
    _unsavedPreference = enabled;
    // 끄기는 저장 응답보다 먼저 적용하여 저장 실패 시에도 추가 전송을 막습니다.
    if (!enabled) {
      shareWhileRunning = false;
      if (sharing || changingSharing) unawaited(setSharing(false));
    }
    _notify();
    try {
      final service = sharingPreferenceService;
      if (service != null) {
        if (!service.isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
        await service.save(enabled).timeout(const Duration(seconds: 15));
        if (!service.isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
      }
      if (_disposed || generation != _preferenceGeneration) return;
      shareWhileRunning = enabled;
      _unsavedPreference = null;
    } catch (_) {
      if (_disposed || generation != _preferenceGeneration) return;
      shareWhileRunning = false;
      sharingPreferenceError = '위치 공유 설정을 저장하지 못했습니다. 공유는 꺼진 상태로 유지합니다.';
      if (sharing || changingSharing) unawaited(setSharing(false));
    } finally {
      if (!_disposed && generation == _preferenceGeneration) {
        savingSharingPreference = false;
        _notify();
        unawaited(_applySharingPreference());
      }
    }
  }

  Future<void> retrySharingPreference() => _unsavedPreference != null
      ? setShareWhileRunning(_unsavedPreference!)
      : loadSharingPreference();

  Future<void> _applySharingPreference() async {
    if (_disposed || loadingSharingPreference || savingSharingPreference) {
      return;
    }
    if (!shareWhileRunning) {
      if (sharing || changingSharing) await setSharing(false);
    } else if (canShareLocation && !sharing && !changingSharing) {
      await setSharing(true);
    }
  }

  LocationTrackingMode get _trackingMode {
    if (_disposed || locationFailure != null) {
      return LocationTrackingMode.stopped;
    }
    if (runSession?.isRunning == true ||
        ((_active && (groupPreparing || groupPrepared))) ||
        (startingRun &&
            _active &&
            _runStartGeneration == _activityGeneration)) {
      return LocationTrackingMode.recording;
    }
    return _active ? LocationTrackingMode.map : LocationTrackingMode.stopped;
  }

  Future<void> _syncTracking() async {
    try {
      await _tracker.setMode(_trackingMode);
    } catch (_) {
      if (_disposed) return;
      locationFailure = const LocationFailure(LocationProblem.unavailable);
      groupPrepared = false;
      runSession?.pause();
      unawaited(_saveCheckpoint());
      _runTimer?.cancel();
      position = null;
      if (sharing || changingSharing) unawaited(setSharing(false));
      _notify();
    }
  }

  void _startTimers() {
    _heartbeat?.cancel();
    _runTimer?.cancel();
    if (!_active || _disposed) return;
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    if (runSession?.isRunning == true) {
      _runTimer = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || locating || !_active) return;
    await restoreRun();
    if (_disposed || locating || !_active) return;
    if (!sharingPreferenceLoaded) unawaited(loadSharingPreference());
    locating = true;
    locationFailure = null;
    _notify();
    final generation = _activityGeneration;
    try {
      final fix = await locationService.current(requestPermission: true);
      if (_disposed || !_active || generation != _activityGeneration) return;
      _acceptPosition(fix);
      await _syncTracking();
      _startTimers();
    } on LocationFailure catch (error, stack) {
      if (error.problem == LocationProblem.unavailable) {
        ErrorReporter.report('run_tracking', stack);
      }
      if (!_disposed && generation == _activityGeneration) {
        locationFailure = error;
      }
    } catch (_) {
      if (!_disposed && generation == _activityGeneration) {
        locationFailure = const LocationFailure(LocationProblem.unavailable);
      }
    } finally {
      if (!_disposed) {
        locating = false;
        _notify();
        if (_active && generation != _activityGeneration && !startingRun) {
          unawaited(start());
        }
      }
    }
  }

  void _acceptPosition(LocationFix fix) {
    if (_disposed || (!_active && runSession?.isRunning != true)) return;
    runSession?.accept(fix);
    if ((sharing || runSession?.isRunning == true) && !fix.isUsable) {
      unawaited(
        _locationLost(const LocationFailure(LocationProblem.unavailable)),
      );
      return;
    }
    position = fix;
    locationFailure = null;
    if (_active) _notify();
    if (_active && sharing && !changingSharing) unawaited(_publish());
  }

  Future<void> _tick() async {
    if (_disposed || !_active || locating) return;
    final generation = _activityGeneration;
    try {
      final fix = await locationService.current();
      if (_disposed || !_active || generation != _activityGeneration) return;
      _acceptPosition(fix);
      if (sharing) await refresh();
    } on LocationFailure catch (error, stack) {
      if (error.problem == LocationProblem.unavailable) {
        ErrorReporter.report('run_tracking', stack);
      }
      if (_active && generation == _activityGeneration) {
        await _locationLost(error);
      }
    } catch (_) {
      if (_active && generation == _activityGeneration) {
        await _locationLost(const LocationFailure(LocationProblem.unavailable));
      }
    }
  }

  Future<void> _locationLost(LocationFailure error) async {
    if (_disposed) return;
    locationFailure = error;
    groupPrepared = false;
    runSession?.pause();
    unawaited(_saveCheckpoint());
    _runTimer?.cancel();
    _activityGeneration++;
    position = null;
    unawaited(_syncTracking());
    if (sharing || changingSharing) await setSharing(false);
    _notify();
  }

  Future<void> startRun() async {
    await restoreRun();
    if (!_recoveryLoaded || !runHistory.service.isCurrentOwner) return;
    if (_disposed ||
        !_active ||
        startingRun ||
        groupPreparing ||
        groupPrepared ||
        savingRun ||
        runSession?.isRunning == true ||
        runSession?.isFinished == true) {
      return;
    }
    startingRun = true;
    if (!sharingPreferenceLoaded) unawaited(loadSharingPreference());
    final generation = _runStartGeneration = ++_activityGeneration;
    runError = null;
    _notify();
    try {
      final fix = await locationService.current(requestPermission: true);
      if (_disposed || !_active || generation != _activityGeneration) return;
      if (!fix.isUsable) {
        runError = '정확한 현재 위치를 확인한 뒤 러닝을 시작해 주세요.';
        return;
      }
      locationFailure = null;
      final ready = await _tracker.setMode(
        LocationTrackingMode.recording,
        waitForFix: true,
      );
      if (_disposed || !_active || generation != _activityGeneration) return;
      if (ready == null || locationFailure != null || !ready.isUsable) {
        runError = locationFailure?.message ?? '위치 측정을 시작하지 못했습니다.';
        return;
      }
      _acceptPosition(ready);
      if (runSession == null) {
        runSession = RunSession(ready);
      } else {
        runSession!.resume(ready);
      }
      _startTimers();
      recoveredRun = false;
      await _saveCheckpoint();
      if (!_disposed && checkpointStore != null) {
        _checkpointTimer ??= Timer.periodic(
          const Duration(seconds: 5),
          (_) => unawaited(_saveCheckpoint()),
        );
      }
    } on LocationFailure catch (error, stack) {
      if (error.problem == LocationProblem.unavailable) {
        ErrorReporter.report('run_tracking', stack);
      }
      if (!_disposed && generation == _activityGeneration) {
        runError = error.message;
        locationFailure = error;
      }
    } catch (_) {
      if (!_disposed && generation == _activityGeneration) {
        runError = '러닝을 시작하지 못했습니다. 다시 시도해 주세요.';
        locationFailure = const LocationFailure(LocationProblem.unavailable);
      }
    } finally {
      if (!_disposed) {
        startingRun = false;
        await _syncTracking();
        _notify();
        if (shareWhileRunning) unawaited(_applySharingPreference());
      }
    }
  }

  void pauseRun() {
    if (runSession == null) return;
    runSession!.pause();
    unawaited(_saveCheckpoint());
    _activityGeneration++;
    _runTimer?.cancel();
    if (sharing || changingSharing) unawaited(setSharing(false));
    unawaited(_syncTracking());
    _notify();
  }

  Future<RunSummary?> finishRun({
    RunTemperature? Function(DateTime)? temperatureAtEnd,
  }) async {
    final session = runSession;
    if (_disposed || session == null || savingRun) return null;
    savingRun = true;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
    final summary = session.finish(temperatureAtEnd: temperatureAtEnd);
    await _saveCheckpoint();
    _activityGeneration++;
    _runTimer?.cancel();
    unawaited(_syncTracking());
    runError = null;
    savingRun = true;
    _notify();
    try {
      // 위치 공유 정리 중 연결이 끊겨도 완료 기록의 기기 저장은 지연하지 않습니다.
      if (sharing || changingSharing) unawaited(setSharing(false));
      await runHistory.save(summary);
      if (checkpointStore != null) {
        final cleared = _checkpointWrites.then((_) => checkpointStore!.clear());
        _checkpointWrites = cleared.catchError((Object _) {});
        await cleared;
      }
      if (_disposed) return null;
      runSession = null;
      recoveredRun = false;
      _checkpointTimer?.cancel();
      _checkpointTimer = null;
      return summary;
    } catch (error, stack) {
      ErrorReporter.report('run_tracking', stack);
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
    if (value && !canShareLocation) {
      sharingError = '러닝 중 정확한 현재 위치가 확인될 때만 공유할 수 있습니다.';
      _notify();
      return;
    }
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
      if (!canShareLocation || generation != _generation) return;
      final fix = position;
      if (fix == null || !fix.isUsable) {
        sharingError = '정확한 현재 위치를 확인한 뒤 공유할 수 있습니다.';
        return;
      }
      await _enqueue(() async {
        if (canShareLocation && generation == _generation) {
          await runnerService.publish(fix);
        }
      });
      if (!canShareLocation || generation != _generation) return;
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
    } catch (error, stack) {
      ErrorReporter.report('run_tracking', stack);
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
    if (!canShareLocation ||
        !sharing ||
        fix == null ||
        !fix.isUsable ||
        (_lastPublished != null &&
            DateTime.now().difference(_lastPublished!) <
                const Duration(seconds: 5))) {
      return;
    }
    _lastPublished = DateTime.now();
    try {
      await _enqueue(() async {
        if (canShareLocation && sharing && generation == _generation) {
          await runnerService.publish(fix);
        }
      });
    } catch (error, stack) {
      ErrorReporter.report('run_tracking', stack);
      if (!_disposed && sharing && generation == _generation) {
        await setSharing(false);
        sharingError = _message(error);
        _notify();
      }
    }
  }

  void _scheduleRefresh() {
    if (!canShareLocation || !sharing || _refreshTimer?.isActive == true) {
      return;
    }
    _refreshTimer = Timer(const Duration(seconds: 1), refresh);
  }

  Future<void> refresh() async {
    if (!canShareLocation || !sharing || _refreshing) return;
    _refreshing = true;
    final generation = _generation;
    final radius = radiusMeters;
    final revision = _runnerRevision;
    try {
      final result = await runnerService.nearby(radius);
      if (!_disposed &&
          sharing &&
          generation == _generation &&
          radius == radiusMeters &&
          revision == _runnerRevision) {
        runners = result;
        sharingError = null;
        _notify();
      }
    } catch (error, stack) {
      ErrorReporter.report('run_tracking', stack);
      if (!_disposed && generation == _generation) {
        runners = [];
        sharingError = _message(error);
        _notify();
      }
    } finally {
      _refreshing = false;
      if (revision != _runnerRevision) unawaited(refresh());
    }
  }

  void setRadius(int radius) {
    if (![500, 1000, 3000, 5000].contains(radius)) return;
    radiusMeters = radius;
    runners = [];
    _notify();
    _scheduleRefresh();
  }

  void hideBlockedRunner(String userId) {
    // 차단 이전에 시작한 지도 조회 응답에서도 해당 러너가 되살아나지 않게 합니다.
    _runnerRevision++;
    runners = runners.where((runner) => runner.id != userId).toList();
    _notify();
  }

  Future<void> setActive(bool active) async {
    if (_disposed || _active == active) return;
    _active = active;
    _activityGeneration++;
    if (active) {
      if (runSession?.isRunning == true) {
        await _syncTracking();
        _startTimers();
        _notify();
      } else {
        await start();
      }
      if (shareWhileRunning) unawaited(_applySharingPreference());
    } else {
      groupPrepared = false;
      unawaited(_saveCheckpoint());
      _heartbeat?.cancel();
      _runTimer?.cancel();
      // 개인 측정은 유지하지만 공개 위치는 즉시 비공개로 전환합니다.
      final stopSharing = sharing || changingSharing ? setSharing(false) : null;
      await _syncTracking();
      await stopSharing;
      if (!_active && runSession?.isRunning != true) position = null;
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
    _checkpointTimer?.cancel();
    runSession?.pause();
    unawaited(_saveCheckpoint());
    _disposed = true;
    _preferenceGeneration++;
    _generation++;
    _activityGeneration++;
    _heartbeat?.cancel();
    _refreshTimer?.cancel();
    _runTimer?.cancel();
    runSession?.pause();
    unawaited(
      _checkpointWrites
          .then((_) => checkpointStore?.close())
          .catchError((Object _) {}),
    );
    unawaited(_tracker.close().catchError((Object _) {}));
    unawaited(runnerService.disconnect().catchError((Object _) {}));
    unawaited(_enqueue(runnerService.stopSharing).catchError((Object _) {}));
    super.dispose();
  }
}
