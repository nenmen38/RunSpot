import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/monetization/level_frames.dart';
import 'package:runquest/features/monetization/profile_cosmetics.dart';
import 'package:runquest/features/progress/models/run_progress.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/shared/maps/run_map.dart';

import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/progress_fakes.dart';
import 'support/run_history_fakes.dart';

RunProgress progressAt(int level) => RunProgress(
  totalXp: level * 100,
  level: level,
  levelXp: 0,
  nextLevelXp: 100,
);

ButtonStyleButton button(WidgetTester tester, int level, String label) =>
    tester.widget<ButtonStyleButton>(
      find.descendant(
        of: find.byKey(ValueKey('frame-$level')),
        matching: find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      ),
    );

void main() {
  test('5단위 레벨마다 다섯 가지 색 구간의 테두리를 받습니다', () {
    expect(LevelFrame.all.map((frame) => frame.level), [
      5, 10, 15, 20, 25, 30, 35, 40, 45, 50, //
    ]);
    expect(LevelFrame.of(5)!.tier, FrameTier.warmup);
    expect(LevelFrame.of(10)!.tier, FrameTier.warmup);
    expect(LevelFrame.of(15)!.tier.color, const Color(0xFF38BDF8));
    expect(LevelFrame.of(30)!.tier, FrameTier.tempo);
    expect(LevelFrame.of(45)!.tier.color, const Color(0xFFEF4444));
    expect(LevelFrame.of(50)!.tier, FrameTier.race);
    expect(LevelFrame.of(5)!.borderWidth, 2);
    expect(LevelFrame.of(50)!.borderWidth, 4);
    expect(LevelFrame.of(10)!.hasAura, isTrue);
    expect(LevelFrame.of(15)!.hasAura, isFalse);
    expect(LevelFrame.of(40)!.pulses, isTrue);
    expect(LevelFrame.of(50)!.isMax, isTrue);
    expect(LevelFrame.unlocked(23).map((frame) => frame.level), [
      5,
      10,
      15,
      20,
    ]);
    expect(LevelFrame.next(23)!.level, 25);
    expect(LevelFrame.unlocked(4), isEmpty);
    expect(LevelFrame.next(60), isNull);
  });

  test('레벨이 오르면 새 테두리가 자동으로 들어오고 착용은 하나만 저장합니다', () async {
    final progress = FakeProgressService(progress: progressAt(12));
    final storage = MemoryFrameStorage()..value = 40;
    final controller = LevelFrameController(progress, storage);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.unlocked.map((frame) => frame.level), [5, 10]);
    // 받지 않은 레벨의 저장값은 착용으로 보지 않습니다.
    expect(controller.equipped, isNull);

    await controller.wear(LevelFrame.of(10));
    expect(controller.equipped!.level, 10);
    expect(storage.value, 10);
    await controller.wear(LevelFrame.of(40));
    expect(controller.equipped!.level, 10);

    progress.progress = progressAt(26);
    await controller.refresh();
    expect(controller.unlocked.map((frame) => frame.level), [
      5,
      10,
      15,
      20,
      25,
    ]);
    expect(controller.next!.level, 30);
    await controller.wear(LevelFrame.of(25));
    expect(controller.equipped!.level, 25);
    await controller.wear(null);
    expect(controller.equipped, isNull);
    expect(storage.value, isNull);
  });

  testWidgets('보관함에서 레벨 테두리를 착용하고 해제합니다', (tester) async {
    final controller = LevelFrameController(
      FakeProgressService(progress: progressAt(12)),
      MemoryFrameStorage(),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileCosmetics.store(levelFrames: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('레벨 보상 테두리'), findsOneWidget);
    expect(find.text('Lv 10 워밍업 테두리'), findsOneWidget);
    expect(find.text('Lv 5 워밍업 테두리'), findsOneWidget);
    expect(find.text('Lv 15 이지런 테두리'), findsNothing);
    expect(find.textContaining('다음 보상은 Lv 15'), findsOneWidget);
    expect(button(tester, 10, '해제').onPressed, isNull);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('frame-10')),
        matching: find.text('착용'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.equipped!.level, 10);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('frame-10')),
        matching: find.text('착용 중'),
      ),
      findsOneWidget,
    );
    expect(button(tester, 10, '착용').onPressed, isNull);
    expect(button(tester, 10, '해제').onPressed, isNotNull);
    expect(button(tester, 5, '해제').onPressed, isNull);

    // 다른 테두리를 착용하면 앞의 테두리는 자동으로 벗습니다.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('frame-5')),
        matching: find.text('착용'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.equipped!.level, 5);
    expect(button(tester, 10, '해제').onPressed, isNull);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('frame-5')),
        matching: find.text('해제'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.equipped, isNull);
    expect(find.text('착용 중'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('맥동·MAX 테두리 미리보기를 그리고 동작 줄이기에서는 멈춥니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            LevelFrameBadge(frame: LevelFrame.of(40)!),
            LevelFrameBadge(frame: LevelFrame.of(50)!),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LevelFrameBadge(frame: LevelFrame.of(50)!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Lv 50 레이스 테두리 미리보기'), findsOneWidget);
  });

  testWidgets('착용한 테두리를 러닝 지도의 내 위치 원에 보냅니다', (tester) async {
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
    addTearDown(location.updates.close);
    final frames = LevelFrameController(
      FakeProgressService(progress: progressAt(20)),
      MemoryFrameStorage(),
    );
    await frames.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: map,
            mapBridgeFactory: FakeMapBridge.new,
            levelFrames: frames,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<RunMap>(find.byType(RunMap)).positionFrame, isNull);

    await frames.wear(LevelFrame.of(20));
    await tester.pump();
    expect(tester.widget<RunMap>(find.byType(RunMap)).positionFrame, 20);

    await frames.wear(null);
    await tester.pump();
    expect(tester.widget<RunMap>(find.byType(RunMap)).positionFrame, isNull);

    await tester.pumpWidget(const SizedBox());
    frames.dispose();
    map.dispose();
    history.dispose();
  });

  test('개발용 시험 레벨은 테두리 계산에만 쓰고 서버 레벨은 그대로 둡니다', () async {
    final progress = FakeProgressService(progress: progressAt(1));
    final controller = LevelFrameController(
      progress,
      MemoryFrameStorage(),
      levelOverride: 50,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.level, 50);
    expect(controller.unlocked, hasLength(10));
    expect(controller.next, isNull);
    await controller.wear(LevelFrame.of(50));
    expect(controller.equipped!.level, 50);
    expect(progress.progress.level, 1);
    // 테스트 실행은 디버그 모드라도 DEV_LEVEL을 주지 않으면 덮어쓰지 않습니다.
    expect(devLevelOverride(), isNull);
  });
}
