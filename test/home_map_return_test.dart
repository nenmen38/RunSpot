import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/shared/maps/run_map.dart';

import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';

void main() {
  testWidgets('지도 이동 후 마지막 터치에서 5초 뒤 내 위치로 돌아온다', (tester) async {
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    final bridge = FakeMapBridge();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: controller,
            mapBridgeFactory: () => bridge,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<RunMap>(find.byType(RunMap)).controller;
    final before = map.command;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RunMap)),
    );
    await gesture.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(seconds: 6));
    expect(map.command, same(before));
    await gesture.up();
    await tester.pump(const Duration(seconds: 4));
    expect(map.command, same(before));
    await tester.tapAt(tester.getCenter(find.byType(RunMap)));
    await tester.pump(const Duration(seconds: 4));
    expect(map.command, same(before));
    await tester.pump(const Duration(seconds: 1));
    expect(map.command, isNot(same(before)));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    history.dispose();
    await location.updates.close();
  });
}
