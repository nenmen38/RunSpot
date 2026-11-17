import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/widgets/run_controls.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';

void main() {
  Future<LiveMapController> show(WidgetTester tester) async {
    final location = FakeLocationService();
    addTearDown(location.updates.close);
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) =>
                RunControls(controller: controller, onFinish: () {}),
          ),
        ),
      ),
    );
    await controller.start();
    await tester.pump();
    return controller;
  }

  testWidgets('러닝 시작을 누르면 3·2·1을 센 뒤 측정을 시작합니다', (tester) async {
    final controller = await show(tester);
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(find.text('곧 출발해요'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(controller.runSession, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('곧 출발해요'), findsNothing);
    expect(controller.runSession?.isRunning, isTrue);
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('카운트다운 중 취소하면 시작하지 않습니다', (tester) async {
    final controller = await show(tester);
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(controller.runSession, isNull);
    expect(find.text('러닝 시작'), findsOneWidget);
    controller.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
