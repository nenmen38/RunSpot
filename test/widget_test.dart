import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/app/mobile_app_viewport.dart';
import 'package:runquest/app/run_quest_shell.dart';
import 'package:runquest/features/home/live_map_controller.dart';
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
      runHistory: RunHistoryController(FakeRunRecordService()),
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
