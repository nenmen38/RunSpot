import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/group_running/data/group_service.dart';
import 'package:runquest/features/group_running/group_controller.dart';
import 'package:runquest/features/group_running/models/running_group.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/shared/maps/run_map.dart';

import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';
import 'support/wallet_fakes.dart';

/// 내 위치(37.5665, 126.978)에서 북쪽으로 [meters]m 떨어진 러너입니다.
LiveRunner runner(
  String id,
  double meters, {
  bool friend = true,
  String? frame = 'aura',
  String color = '#3182F6',
  Duration later = Duration.zero,
}) => LiveRunner.fromJson({
  'user_id': id,
  'nickname': '러너$id',
  'latitude': 37.5665 + meters / 111194.9,
  'longitude': 126.978,
  'distance_m': meters,
  'updated_at': DateTime.now().add(later).toIso8601String(),
  'is_friend': friend,
  'frame': frame,
  'frame_color': frame == null ? null : color,
  'pace_sec': 330,
});

void main() {
  test('주변 러너의 친구 여부·테두리·페이스를 읽고 잘못된 색은 버립니다', () {
    final friend = runner('a', 20);
    expect(friend.isFriend, isTrue);
    expect(friend.hasAura, isTrue);
    expect(friend.frameColor, '#3182F6');
    expect(friend.paceSecPerKm, 330);
    expect(runner('b', 20, color: 'red').frame, isNull);
    // 서버가 아직 갱신되지 않아 새 항목이 없어도 그대로 읽습니다.
    final old = LiveRunner.fromJson({
      'user_id': 'c',
      'nickname': '이전',
      'latitude': 37.0,
      'longitude': 127.0,
      'distance_m': 5,
      'updated_at': DateTime.now().toIso8601String(),
    });
    expect(old.isFriend, isFalse);
    expect(old.frame, isNull);
    expect(old.paceSecPerKm, isNull);
  });

  testWidgets('오라를 착용한 친구와 가까워지면 합쳐진 상태를 지도에 보내고 햅틱을 울립니다', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final service = FakeRunnerService()
      ..runners = [
        runner('a', 450),
        // 친구가 아니면 합쳐지지 않고 테두리만 보입니다.
        runner('b', 10, friend: false, color: '#22C55E'),
        // 빛줄기 거리(600m) 밖의 친구는 아직 잇지 않습니다.
        runner('c', 700, frame: 'basic', color: '#F97316'),
        // 테두리가 없는 친구도 내가 오라를 착용했으면 합쳐집니다.
        runner('d', 500, frame: null),
      ];
    final map = LiveMapController(
      locationService: location,
      runnerService: service,
      runHistory: history,
    );
    addTearDown(location.updates.close);
    final walletService = FakeWalletService()
      ..owned.add(FrameKind.aura)
      ..equipped = FrameKind.aura
      ..color = '#EF4444';
    final wallet = WalletController(walletService);
    await wallet.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: map,
            mapBridgeFactory: FakeMapBridge.new,
            wallet: wallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    RunMap view() => tester.widget<RunMap>(find.byType(RunMap));

    // 450m·500m: 빛줄기만 있고 아직 합쳐지지 않았습니다.
    var aura = view().aura!;
    final nodes = {
      for (final node in aura['nodes'] as List) node['id']: node['color'],
    };
    expect(nodes, {'a': '#3182F6', 'd': '#EF4444'});
    // 나와는 아직 빛줄기이고, 서로 50m인 a와 d만 먼저 합쳐집니다.
    expect(
      (aura['links'] as List)
          .where((link) => link['merged'] == true)
          .map((link) => '${link['a']}-${link['b']}'),
      ['a-d'],
    );
    expect((aura['self'] as Map)['crew'], isNull);
    expect(haptics, isEmpty);
    final frames = {
      for (final marker in view().markers) marker.id: marker.frame?.toJson(),
    };
    expect(frames['a'], {'style': 'aura', 'color': '#3182F6'});
    expect(frames['b'], {'style': 'aura', 'color': '#22C55E'});
    expect(frames['c'], {'style': 'basic', 'color': '#F97316'});
    expect(frames['d'], isNull);

    // 250m로 다가오면 합쳐지고 햅틱이 한 번 울립니다.
    // 위치를 몇 초 평균으로 보정하므로 이전 위치가 섞이지 않게 10초 뒤의 위치로 넣습니다.
    service.runners = [runner('a', 250, later: const Duration(seconds: 10))];
    await map.refresh();
    await tester.pump();
    aura = view().aura!;
    expect((aura['links'] as List).single['merged'], isTrue);
    expect((aura['self'] as Map)['crew'], 0);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);

    // 오라를 벗으면 합체 표시를 끕니다.
    await wallet.wear(null);
    await tester.pump();
    expect(view().aura, isNull);

    await tester.pumpWidget(const SizedBox());
    wallet.dispose();
    map.dispose();
    history.dispose();
  });

  testWidgets('함께 달리는 친구들이 300m 안이면 방장 오라 색 동그라미 하나에 인원수로 보여줍니다', (
    tester,
  ) async {
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final service = FakeRunnerService()
      ..runners = [
        runner('a', 100, color: '#F97316'),
        runner('b', 250, frame: null),
        runner('c', 280, frame: 'basic', color: '#22C55E'),
      ];
    final map = LiveMapController(
      locationService: location,
      runnerService: service,
      runHistory: history,
    );
    addTearDown(location.updates.close);
    final groups = GroupController(_RunningGroup(), map);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: map,
            mapBridgeFactory: FakeMapBridge.new,
            groupController: groups,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await groups.refresh();
    await tester.pump();
    final markers = tester.widget<RunMap>(find.byType(RunMap)).markers;
    final bubble = markers.single;
    expect(bubble.memberCount, 3);
    expect(bubble.nickname, '함께 달리기 3명');
    // 함께 달리기를 신청한 a의 오라 색입니다.
    expect(bubble.frame!.toJson(), {'style': 'aura', 'color': '#F97316'});

    await tester.pumpWidget(const SizedBox());
    groups.dispose();
    map.dispose();
    history.dispose();
  });
}

/// a가 신청해 a·b·c와 내가 함께 달리고 있는 그룹입니다.
class _RunningGroup implements GroupService {
  @override
  final ownerId = 'owner';
  @override
  bool get isCurrentOwner => true;

  @override
  Future<GroupDashboard> load() async => GroupDashboard.fromJson({
    'server_now': DateTime.now().toUtc().toIso8601String(),
    'groups': [
      {
        'id': 'g',
        'host_id': 'a',
        'state': 'running',
        'my_status': 'accepted',
        'starts_at': DateTime.now().toUtc().toIso8601String(),
        'members': [
          for (final id in ['a', 'b', 'c', 'owner'])
            {'user_id': id, 'nickname': id, 'status': 'accepted'},
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
  }) async => 'g';
}
