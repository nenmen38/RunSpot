import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/app/mobile_app_viewport.dart';
import 'package:runquest/app/run_quest_shell.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/widgets/run_route_layer.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';

class MemoryTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1cAAAAASUVORK5CYII=',
        ),
      );
}

void main() {
  Future<LiveMapController> showApp(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final location = FakeLocationService();
    addTearDown(location.updates.close);
    final controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: RunHistoryController(
        FakeRunRecordService(),
        outbox: FakeRunOutbox(),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: MobileAppViewport(
          child: RunQuestShell(
            mapController: controller,
            mapTileProvider: MemoryTileProvider(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('홈은 현재 위치 지도이며 코스 만들기 탭이 없습니다', (tester) async {
    await showApp(tester, const Size(390, 844));
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('RunSpot'), findsOneWidget);
    expect(find.bySemanticsLabel('내 현재 위치'), findsOneWidget);
    expect(find.text('위치 공유'), findsOneWidget);
    expect(find.text('러닝 시작'), findsOneWidget);
    expect(find.text('러닝 종료'), findsOneWidget);
    expect(find.text('코스'), findsNothing);
    expect(find.text('코스 만들기'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('홈에서 시작과 일시 정지 후 종료 결과를 확인합니다', (tester) async {
    final controller = await showApp(tester, const Size(320, 568));
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(controller.runSession!.isRunning, isTrue);
    expect(find.text('러닝 중'), findsOneWidget);
    expect(find.text('거리'), findsOneWidget);
    expect(find.text('현재 페이스'), findsOneWidget);
    expect(find.text('평균 페이스'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('일시 정지').last);
    await tester.pump();
    expect(controller.runSession!.isRunning, isFalse);
    await tester.tap(find.text('러닝 계속'));
    await tester.pump();
    expect(controller.runSession!.isRunning, isTrue);
    await tester.tap(find.text('러닝 종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(controller.runSession!.isRunning, isTrue);
    await tester.tap(find.text('러닝 종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('러닝 완료'), findsOneWidget);
    expect(controller.runSession, isNull);
    expect(controller.runHistory.records, hasLength(1));
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('러닝 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('내 기록'));
    await tester.pumpAndSettle();
    expect(find.text('내 기록'), findsOneWidget);
    expect(find.text('0.00 km'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('다른 탭을 다녀와도 지도와 공유 상태를 유지합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.sharing, isTrue);
    await tester.tap(find.text('소셜').last);
    await tester.pumpAndSettle();
    expect(find.text('친구 랭킹'), findsOneWidget);
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(controller.sharing, isTrue);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('지도 경로와 페이스를 표시하고 일시 정지 구간을 연결하지 않습니다', (tester) async {
    final controller = await showApp(tester, const Size(320, 568));
    final location = controller.locationService as FakeLocationService;
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    final origin = controller.position!.recordedAt;
    location.updates.add(
      testFix(
        latitude: 37.567,
        recordedAt: origin.add(const Duration(seconds: 10)),
      ),
    );
    await tester.pump();
    expect(controller.runSession!.currentPace, isNotNull);
    final layerFinder = find.byWidgetPredicate(
      (widget) => widget is PolylineLayer,
    );
    expect(find.byType(RunRouteLayer), findsOneWidget);
    var layer = tester.widget<PolylineLayer>(layerFinder);
    expect(layer.polylines.single.points, hasLength(2));
    await tester.tap(find.text('일시 정지').last);
    await tester.pump();
    location.fix = testFix(
      latitude: 37.57,
      recordedAt: origin.add(const Duration(seconds: 11)),
    );
    await tester.tap(find.text('러닝 계속'));
    await tester.pump();
    location.updates.add(
      testFix(
        latitude: 37.5705,
        recordedAt: origin.add(const Duration(seconds: 16)),
      ),
    );
    await tester.pump();
    layer = tester.widget<PolylineLayer>(layerFinder);
    expect(layer.polylines, hasLength(2));
    expect(layer.polylines.first.points.last.latitude, 37.567);
    expect(layer.polylines.last.points.first.latitude, 37.57);
    await controller.finishRun();
    await tester.pump();
    expect(find.byType(RunRouteLayer), findsNothing);
    expect(find.text('현재 페이스'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('좁은 실제 화면에서도 측정값과 지도·종료 버튼이 겹치지 않습니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    addTearDown(location.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: controller,
            onProfileTap: () {},
            tileProvider: MemoryTileProvider(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(find.text('현재 페이스'), findsOneWidget);
    expect(find.text('평균 페이스'), findsOneWidget);
    expect(tester.getSize(find.byType(FlutterMap)).height, greaterThan(200));
    expect(find.text('러닝 종료').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    history.dispose();
  });

  testWidgets('화면 잠금 수명 주기 뒤에도 러닝 중 표시와 측정을 유지합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    final location = controller.locationService as FakeLocationService;
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    final session = controller.runSession!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    location.updates.add(testFix(latitude: 37.568));
    await tester.pump();
    expect(session.isRunning, isTrue);
    expect(session.distanceMeters, greaterThan(100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.runSession, same(session));
    expect(find.text('러닝 중'), findsOneWidget);
    expect(find.text('일시 정지'), findsWidgets);
    expect(controller.sharing, isFalse);
    expect(location.watchModes, [false, true]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('첫 GPS 응답이 없으면 시작을 실패 처리하고 백그라운드 측정을 해제합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    final location = controller.locationService as FakeLocationService;
    location.emitInitialFix = false;
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(controller.startingRun, isTrue);
    await tester.pump(const Duration(seconds: 21));
    expect(controller.startingRun, isFalse);
    expect(controller.runSession, isNull);
    expect(controller.runError, isNotNull);
    expect(location.activeWatches, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('오프라인으로 종료해도 기기 저장 결과를 표시하고 다시 시작합니다', (tester) async {
    final controller = await showApp(tester, const Size(320, 568));
    final service = controller.runHistory.service as FakeRunRecordService;
    service.saveFailure = const SocketException('오프라인');
    service.listFailure = const SocketException('오프라인');
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    await tester.tap(find.text('러닝 종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('기기에 저장됨'), findsOneWidget);
    expect(find.text('서버 저장 대기'), findsOneWidget);
    expect(controller.runSession, isNull);
    expect((controller.runHistory.outbox as FakeRunOutbox).rows, hasLength(1));
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(controller.runSession!.isRunning, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 568),
    const Size(1280, 900),
    const Size(900, 500),
  ]) {
    testWidgets('지도와 버튼은 ${size.width} 너비에서도 겹치지 않습니다', (tester) async {
      await showApp(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
