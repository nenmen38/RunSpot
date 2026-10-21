import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/group_running/data/group_service.dart';
import 'package:runquest/features/group_running/group_controller.dart';
import 'package:runquest/features/group_running/models/running_group.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';

class _Groups implements GroupService {
  @override
  final ownerId = 'owner';
  @override
  bool isCurrentOwner = true;
  bool fail = false;
  String state = 'lobby';
  DateTime? startsAt;
  final actions = <String>[];
  int claims = 0;
  @override
  Future<GroupDashboard> load() async {
    if (fail) throw StateError('연결 실패');
    return GroupDashboard.fromJson({
      'server_now': DateTime.now().toUtc().toIso8601String(),
      'groups': [
        {
          'id': 'group',
          'host_id': 'owner',
          'state': state,
          'my_status': 'accepted',
          'starts_at': startsAt?.toIso8601String(),
          'members': [
            {
              'user_id': 'owner',
              'nickname': '내이름',
              'status': 'accepted',
              'ready': true,
              'client_run_id': null,
              'distance_m': null,
              'duration_sec': null,
            },
          ],
        },
      ],
    });
  }

  @override
  Future<String> change(
    String operation, {
    String? groupId,
    String? targetId,
    String? clientId,
  }) async {
    actions.add(operation);
    if (operation == 'join_run') {
      claims++;
      expect(clientId, isNotNull);
    }
    return 'group';
  }
}

void main() {
  testWidgets('GPS 준비 뒤 서버 공동 출발 시각에 한 번만 개인 측정을 시작합니다', (tester) async {
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final map = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    final service = _Groups();
    final groups = GroupController(service, map);
    await tester.pump();
    await groups.prepare('group');
    expect(map.groupPrepared, isTrue);
    expect(map.runSession, isNull);
    service.state = 'running';
    service.startsAt = DateTime.now().toUtc().subtract(
      const Duration(seconds: 1),
    );
    await groups.refresh();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(map.runSession?.isRunning, isTrue);
    expect(service.claims, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(service.claims, 1);
    groups.dispose();
    map.dispose();
    history.dispose();
    await location.updates.close();
    await tester.pump();
  });

  testWidgets('백그라운드로 가면 GPS 준비를 해제하고 복귀 시 자동 출발하지 않습니다', (tester) async {
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final map = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    final service = _Groups();
    final groups = GroupController(service, map);
    await tester.pump();
    await groups.prepare('group');
    groups.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(map.groupPrepared, isFalse);
    expect(service.actions, contains('unready'));
    service.state = 'running';
    service.startsAt = DateTime.now().toUtc().subtract(
      const Duration(seconds: 1),
    );
    groups.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(map.runSession, isNull);
    expect(service.claims, 0);
    groups.dispose();
    map.dispose();
    history.dispose();
    await location.updates.close();
    await tester.pump();
  });

  testWidgets('오래된 출발·조회 실패·기존 개인 러닝은 자동 출발을 막습니다', (tester) async {
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final map = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    final service = _Groups();
    final groups = GroupController(service, map);
    await tester.pump();
    await groups.prepare('group');
    service.state = 'running';
    service.startsAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 1),
    );
    await groups.refresh();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(map.runSession, isNull);
    expect(map.groupPrepared, isFalse);
    service.state = 'lobby';
    service.startsAt = null;
    await groups.prepare('group');
    service.fail = true;
    await groups.refresh();
    expect(groups.groups, isEmpty);
    expect(map.groupPrepared, isFalse);
    service.fail = false;
    await map.startRun();
    await groups.prepare('group');
    expect(map.groupPrepared, isFalse);
    expect(map.runSession?.isRunning, isTrue);
    groups.dispose();
    map.dispose();
    history.dispose();
    await location.updates.close();
    await tester.pump();
  });
}
