import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home/live_map_controller.dart';
import 'data/group_service.dart';
import 'models/running_group.dart';

class GroupController extends ChangeNotifier with WidgetsBindingObserver {
  GroupController(this.service, this.map) {
    if (service.ownerId != map.runHistory.service.ownerId) {
      throw ArgumentError('그룹과 러닝의 계정이 다릅니다.');
    }
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_foreground && !busy) unawaited(refresh(force: false));
    });
    _countdown = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );
    unawaited(refresh());
  }
  final GroupService service;
  final LiveMapController map;
  List<RunningGroup> groups = [];
  String? error;
  bool busy = false;
  bool loading = false;
  bool _disposed = false;
  bool _foreground = true;
  Timer? _timer;
  Timer? _countdown;
  String? preparedGroupId;
  String? _startingGroup;
  String? _claimGroup;
  String? _claimClient;
  DateTime? _serverNow;
  final _sinceSnapshot = Stopwatch();
  DateTime? _lastLoad;
  bool _claiming = false;
  DateTime? get serverNow => _serverNow?.add(_sinceSnapshot.elapsed);
  int? secondsUntil(RunningGroup group) {
    final now = serverNow;
    return group.startsAt == null || now == null
        ? null
        : (group.startsAt!.difference(now).inMilliseconds / 1000).ceil();
  }

  /// 위치 준비와 서버 출발 예약이 모두 유효한 본인 그룹만 표시합니다.
  RunningGroup? get countdownGroup {
    if (_disposed ||
        !_foreground ||
        !service.isCurrentOwner ||
        !map.groupPrepared) {
      return null;
    }
    return groups
        .where(
          (group) =>
              group.id == preparedGroupId &&
              group.myStatus == 'accepted' &&
              (group.state == 'scheduled' || group.state == 'running') &&
              (secondsUntil(group) ?? 0) > 0,
        )
        .firstOrNull;
  }

  Future<void> refresh({bool force = true}) async {
    if (_disposed || !_foreground || loading || !service.isCurrentOwner) return;
    if (!force &&
        !groups.any((group) => group.active) &&
        _lastLoad != null &&
        DateTime.now().difference(_lastLoad!) < const Duration(seconds: 30)) {
      return;
    }
    _lastLoad = DateTime.now();
    loading = true;
    final watch = Stopwatch()..start();
    try {
      final dashboard = await service.load().timeout(
        const Duration(seconds: 10),
      );
      if (_disposed || !_foreground || !service.isCurrentOwner) return;
      // 취소한 그룹은 기록에 남기지 않습니다.
      groups = [
        for (final group in dashboard.groups)
          if (group.state != 'cancelled') group,
      ];
      _serverNow = dashboard.serverNow.add(
        Duration(microseconds: watch.elapsedMicroseconds ~/ 2),
      );
      _sinceSnapshot
        ..reset()
        ..start();
      error = _prepareFailed ? _prepareMessage : null;
      final prepared = groups
          .where(
            (group) =>
                group.id == preparedGroupId &&
                group.active &&
                group.myStatus == 'accepted',
          )
          .firstOrNull;
      if (preparedGroupId != null && (prepared == null || !map.groupPrepared)) {
        // 홈에서 준비를 취소했으면 같은 출발에 다시 준비하지 않습니다.
        if (prepared != null) _skipGroup = prepared.id;
        preparedGroupId = null;
        await map.cancelGroupPreparation();
      }
      if (_claimGroup != null) await _claim();
    } catch (_) {
      if (!_disposed) {
        groups = [];
        preparedGroupId = null;
        await map.cancelGroupPreparation();
        error = '그룹 상태를 확인하지 못했습니다. 연결을 확인해 주세요.';
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
    await _autoPrepare();
  }

  static const _prepareMessage =
      '위치를 확인하지 못해 자동 출발을 준비하지 못했습니다. 위치 권한과 진행 중인 개인 러닝을 확인해 주세요.';
  bool _preparing = false;
  bool _prepareFailed = false;
  String? _skipGroup;

  /// 방장이 출발을 예약하면 따로 누르지 않아도 위치를 잡아 두고,
  /// 출발 시각이 되면 바로 측정을 시작합니다. 위치는 그룹에 보내지 않습니다.
  Future<void> _autoPrepare() async {
    if (_disposed ||
        !_foreground ||
        _preparing ||
        preparedGroupId != null ||
        !service.isCurrentOwner ||
        map.runSession != null) {
      return;
    }
    final group = groups
        .where(
          (group) =>
              group.myStatus == 'accepted' &&
              (group.state == 'scheduled' || group.state == 'running') &&
              (secondsUntil(group) ?? 0) > 0,
        )
        .firstOrNull;
    if (group == null) _prepareFailed = false;
    if (group == null || group.id == _skipGroup) return;
    _preparing = true;
    try {
      if (!await map.prepareGroupRun()) throw StateError('위치 준비 실패');
      if (_disposed || !_foreground || !service.isCurrentOwner) {
        await map.cancelGroupPreparation();
        return;
      }
      preparedGroupId = group.id;
      _prepareFailed = false;
      if (error == _prepareMessage) error = null;
    } catch (_) {
      await map.cancelGroupPreparation();
      _skipGroup = group.id;
      if (!_disposed && map.runSession == null) {
        _prepareFailed = true;
        error = _prepareMessage;
      }
    } finally {
      _preparing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> change(
    String operation, {
    String? groupId,
    String? targetId,
  }) async {
    if (busy || _disposed || !service.isCurrentOwner) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await service
          .change(operation, groupId: groupId, targetId: targetId)
          .timeout(const Duration(seconds: 15));
      if (operation == 'cancel' || operation == 'leave') {
        if (preparedGroupId == groupId) {
          preparedGroupId = null;
          await map.cancelGroupPreparation();
        }
      }
      await refresh();
    } catch (exception) {
      if (!_disposed) {
        error =
            exception is PostgrestException &&
                ['P0001', '22023', '42501'].contains(exception.code)
            ? exception.message
            : '그룹 요청을 처리하지 못했습니다. 새로고침 후 확인해 주세요.';
      }
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _tick() {
    if (_disposed || !_foreground || !service.isCurrentOwner) return;
    if (preparedGroupId == null) return;
    final group = groups
        .where((group) => group.id == preparedGroupId)
        .firstOrNull;
    if (group == null) return;
    final seconds = secondsUntil(group);
    if (seconds == null) return;
    if (seconds <= 0 && _startingGroup == null) {
      unawaited(_start(group, seconds));
    }
    notifyListeners();
  }

  Future<void> _start(RunningGroup group, int seconds) async {
    _startingGroup = group.id;
    preparedGroupId = null;
    try {
      // 오래된 응답·백그라운드 복귀로 출발을 놓쳤으면 자동 측정하지 않습니다.
      if (seconds < -3 || _sinceSnapshot.elapsed > const Duration(seconds: 5)) {
        throw StateError('출발 시간 경과');
      }
      final clientId = await map.startPreparedGroupRun();
      if (clientId == null) {
        throw StateError('위치 준비 만료');
      }
      _claimGroup = group.id;
      _claimClient = clientId;
      await _claim();
      await refresh();
    } catch (_) {
      await map.cancelGroupPreparation();
      if (!_disposed) error = '그룹 연결을 완료하지 못했습니다. 홈에서 개인 측정 상태를 확인해 주세요.';
    } finally {
      _startingGroup = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _claim() async {
    if (_claimGroup == null || _claiming || !service.isCurrentOwner) return;
    _claiming = true;
    try {
      await service
          .change('join_run', groupId: _claimGroup, clientId: _claimClient)
          .timeout(const Duration(seconds: 10));
    } on PostgrestException catch (exception) {
      if (exception.code == 'P0001' || exception.code == '42501') {
        _claimGroup = null;
        _claimClient = null;
      }
      rethrow;
    } finally {
      _claiming = false;
    }
    _claimGroup = null;
    _claimClient = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      preparedGroupId = null;
      unawaited(map.cancelGroupPreparation());
    } else {
      // 설정에서 위치 권한을 바꾸고 돌아왔을 수 있으니 다시 준비해 봅니다.
      _skipGroup = null;
      unawaited(refresh());
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _countdown?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(map.cancelGroupPreparation());
    super.dispose();
  }
}
