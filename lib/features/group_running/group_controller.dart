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
      groups = dashboard.groups;
      _serverNow = dashboard.serverNow.add(
        Duration(microseconds: watch.elapsedMicroseconds ~/ 2),
      );
      _sinceSnapshot
        ..reset()
        ..start();
      error = null;
      final prepared = groups
          .where(
            (group) =>
                group.id == preparedGroupId &&
                group.active &&
                group.myStatus == 'accepted',
          )
          .firstOrNull;
      if (preparedGroupId != null && (prepared == null || !map.groupPrepared)) {
        final groupId = preparedGroupId;
        preparedGroupId = null;
        await map.cancelGroupPreparation();
        await service
            .change('unready', groupId: groupId)
            .timeout(const Duration(seconds: 10));
      }
      if (_claimGroup != null) await _claim();
      if (prepared?.state == 'lobby' && map.groupPrepared) {
        await service
            .change('ready', groupId: prepared!.id)
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {
      if (!_disposed) {
        groups = [];
        preparedGroupId = null;
        await map.cancelGroupPreparation();
        error = '그룹 상태를 확인하지 못했습니다. 연결을 확인해 주세요. GPS 준비를 다시 확인하세요.';
      }
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
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

  Future<void> prepare(String groupId) async {
    if (busy || _disposed || preparedGroupId != null || !service.isCurrentOwner) {
      return;
    }
    busy = true;
    notifyListeners();
    try {
      if (!await map.prepareGroupRun()) throw StateError('위치 준비 실패');
      await service
          .change('ready', groupId: groupId)
          .timeout(const Duration(seconds: 10));
      if (_disposed || !_foreground || !service.isCurrentOwner) {
        await map.cancelGroupPreparation();
        return;
      }
      preparedGroupId = groupId;
      error = null;
      await refresh();
    } catch (_) {
      await map.cancelGroupPreparation();
      if (!_disposed) {
        error = 'GPS 준비를 완료하지 못했습니다. 진행 중인 개인 러닝과 위치 권한을 확인해 주세요.';
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
    if (seconds != null && seconds <= 0 && _startingGroup == null) {
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
      final groupId = preparedGroupId;
      preparedGroupId = null;
      unawaited(map.cancelGroupPreparation());
      if (groupId != null && service.isCurrentOwner) {
        unawaited(
          service
              .change('unready', groupId: groupId)
              .then<void>((_) {})
              .catchError((Object _) {}),
        );
      }
    } else {
      unawaited(refresh());
    }
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
