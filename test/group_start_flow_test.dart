import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/app/run_quest_shell.dart';
import 'package:runquest/features/group_running/data/group_service.dart';
import 'package:runquest/features/group_running/group_controller.dart';
import 'package:runquest/features/group_running/group_running_screen.dart';
import 'package:runquest/features/group_running/models/running_group.dart';
import 'package:runquest/features/group_running/widgets/group_start_countdown.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/friend_fakes.dart';
import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';
import 'support/statistics_fakes.dart';

class _AuthStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

class _Service implements GroupService {
  @override
  final ownerId = 'owner';
  @override
  bool isCurrentOwner = true;
  bool host = true;
  bool failStart = false;
  bool quickInvite = false;
  String myStatus = 'accepted';
  String state = 'lobby';
  String friendStatus = 'accepted';
  DateTime? startsAt;
  int starts = 0;

  @override
  Future<GroupDashboard> load() async => GroupDashboard.fromJson({
    'server_now': clock.now().toUtc().toIso8601String(),
    'groups': [
      {
        'id': 'group',
        'host_id': host ? 'owner' : 'friend',
        'state': state,
        'my_status': myStatus,
        'auto_start_on_accept': quickInvite,
        'starts_at': startsAt?.toIso8601String(),
        'members': [
          {
            'user_id': 'owner',
            'nickname': '러너',
            'status': 'accepted',
            'ready': false,
            'client_run_id': null,
            'distance_m': null,
            'duration_sec': null,
          },
          {
            'user_id': 'friend',
            'nickname': '친구',
            'status': friendStatus,
            'ready': false,
            'client_run_id': null,
            'distance_m': null,
            'duration_sec': null,
          },
        ],
      },
    ],
  });

  @override
  Future<String> change(
    String operation, {
    String? groupId,
    String? targetId,
    String? clientId,
  }) async {
    if (operation == 'accept' && quickInvite) myStatus = 'accepted';
    if (operation == 'start' || (operation == 'accept' && quickInvite)) {
      if (failStart) {
        throw const PostgrestException(
          message: '초대한 친구가 수락하면 출발할 수 있어요.',
          code: 'P0001',
        );
      }
      state = 'scheduled';
      startsAt = clock.now().toUtc().add(const Duration(seconds: 10));
    }
    if (operation == 'join_run') starts++;
    return 'group';
  }
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
        pkceAsyncStorage: _AuthStorage(),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<(GroupController, LiveMapController)> show(
    WidgetTester tester,
    _Service service,
  ) async {
    final location = FakeLocationService();
    addTearDown(location.updates.close);
    final map = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: RunHistoryController(
        FakeRunRecordService(),
        outbox: FakeRunOutbox(),
      ),
    );
    final groups = GroupController(service, map, stopwatch: clock.stopwatch);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: RunQuestShell(
          mapController: map,
          mapBridgeFactory: FakeMapBridge.new,
          friendService: FakeFriendService(),
          rankingService: FakeRankingService(),
          groupController: groups,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('소셜').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('함께 달리기 상태'));
    await tester.pumpAndSettle();
    // GPS 준비 버튼 없이, 출발 예약 전에는 위치를 따로 잡지 않습니다.
    expect(find.text('GPS 준비'), findsNothing);
    expect(map.groupPrepared, isFalse);
    return (groups, map);
  }

  for (final host in [true, false]) {
    testWidgets(
      '${host ? '방장은' : '참여자는'} 출발 예약 후 홈으로 이동하고 중앙 카운트다운 뒤 한 번만 출발합니다',
      (tester) async {
        final service = _Service()..host = host;
        final (groups, map) = await show(tester, service);
        if (host) {
          await tester.tap(find.text('10초 뒤 출발'));
        } else {
          service.state = 'scheduled';
          service.startsAt = clock.now().toUtc().add(
            const Duration(seconds: 10),
          );
          await groups.refresh();
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(GroupRunningScreen), findsNothing);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(GroupStartCountdown),
            matching: find.text('9'),
          ),
          findsOneWidget,
        );
        expect(map.runSession, isNull);
        service.startsAt = clock.now().toUtc().add(const Duration(seconds: 3));
        await groups.refresh();
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(GroupStartCountdown),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        service.state = 'running';
        service.startsAt = clock.now().toUtc().subtract(
          const Duration(milliseconds: 100),
        );
        await groups.refresh();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump();
        expect(map.runSession?.isRunning, isTrue);
        expect(service.starts, 1);
        expect(find.text('잠시 후 출발'), findsNothing);
        expect(tester.takeException(), isNull);
        groups.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('사용자 메뉴 초대는 수락만으로 홈 카운트다운을 표시합니다', (tester) async {
    final service = _Service()
      ..host = false
      ..quickInvite = true
      ..myStatus = 'invited';
    final (groups, map) = await show(tester, service);
    await tester.tap(find.text('초대 수락'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 참여'));
    await tester.pump();
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
    expect(service.myStatus, 'accepted');
    expect(groups.countdownGroup?.id, 'group');
    expect(find.byType(GroupRunningScreen), findsNothing);
    expect(find.text('잠시 후 출발'), findsOneWidget);
    expect(map.runSession, isNull);
    groups.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('병합으로 빠졌던 전경 푸시 안내와 초대 화면 이동을 유지합니다', (tester) async {
    final service = _Service();
    final (groups, _) = await show(tester, service);
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('홈').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    PushService.instance.messages.add(
      const PushDestination('group_invite', 'group', 'owner'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('함께 달리기 초대가 도착했어요.'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(GroupRunningScreen), findsOneWidget);
    groups.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('수락한 친구가 없으면 방장의 출발 버튼이 꺼져 있습니다', (tester) async {
    final service = _Service()..friendStatus = 'invited';
    final (groups, _) = await show(tester, service);
    expect(find.text('친구가 초대를 수락하면 바로 출발할 수 있어요.'), findsOneWidget);
    FilledButton start() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '10초 뒤 출발'),
    );
    expect(start().onPressed, isNull);
    service.friendStatus = 'accepted';
    await groups.refresh();
    await tester.pump();
    expect(start().onPressed, isNotNull);
    groups.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('출발 예약이 실패하면 그룹 화면에 남고 카운트다운을 표시하지 않습니다', (tester) async {
    final service = _Service()..failStart = true;
    final (groups, _) = await show(tester, service);
    await tester.tap(find.text('10초 뒤 출발'));
    await tester.pumpAndSettle();
    expect(find.byType(GroupRunningScreen), findsOneWidget);
    expect(find.text('초대한 친구가 수락하면 출발할 수 있어요.'), findsOneWidget);
    expect(find.text('잠시 후 출발'), findsNothing);
    groups.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('카운트다운 중 백그라운드로 가면 표시와 자동 출발을 중단합니다', (tester) async {
    final service = _Service();
    final (groups, map) = await show(tester, service);
    await tester.tap(find.text('10초 뒤 출발'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    groups.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(map.groupPrepared, isFalse);
    expect(find.text('잠시 후 출발'), findsNothing);
    expect(map.runSession, isNull);
    groups.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
