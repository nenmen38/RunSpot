import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:runquest/shared/maps/run_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/run_record_detail_screen.dart';
import 'package:runquest/features/run_history/widgets/saved_run_map.dart';

import 'support/run_history_fakes.dart';
import 'support/map_fakes.dart';

void main() {
  final route = RunRoute([
    [const LatLng(37.5665, 126.978), const LatLng(37.567, 126.9785)],
    [const LatLng(37.57, 126.98), const LatLng(37.571, 126.98)],
  ]);
  final summary = RunSummary(
    clientRunId: 'run-id',
    startedAt: DateTime.utc(2026, 10, 9),
    endedAt: DateTime.utc(2026, 10, 9, 1),
    distanceMeters: 5000,
    duration: const Duration(minutes: 25),
    route: route,
  );
  final record = RunRecord(
    id: 'run-id',
    clientRunId: 'run-id',
    startedAt: summary.startedAt,
    endedAt: summary.endedAt,
    distanceMeters: 5000,
    durationSeconds: 1500,
  );

  test('경로는 원본 변경과 직렬화 결과 변경에서 격리됩니다', () {
    final segment = [const LatLng(37.5665123456, 126.978)];
    final stored = RunRoute([segment]);
    segment.clear();
    final encoded = stored.toJson();
    encoded.first.first[0] = 0;
    expect(stored.segments.single.single.latitude, 37.5665123456);
    expect(
      RunRoute.fromJson(jsonDecode(jsonEncode(route.toJson()))).toJson(),
      route.toJson(),
    );
  });

  test('잘못된 형태와 범위를 가진 좌표를 거절합니다', () {
    for (final value in [
      null,
      {},
      [[]],
      [
        [
          ['37', 126],
        ],
      ],
      [
        [
          [91, 126],
        ],
      ],
      [
        [
          [37, 181],
        ],
      ],
      [
        [
          [37, double.nan],
        ],
      ],
    ]) {
      expect(() => RunRoute.fromJson(value), throwsFormatException);
    }
    expect(RunRoute.fromJson([]).isEmpty, isTrue);
  });

  for (final size in [
    const Size(320, 568),
    const Size(430, 932),
    const Size(1024, 768),
  ]) {
    testWidgets('지도 전체 경로와 단절 구간을 표시합니다 (${size.width})', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeRunRecordService()..routes[record.id] = route;
      final controller = RunHistoryController(service, outbox: FakeRunOutbox());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: RunRecordDetailScreen(
            record: record,
            controller: controller,
            mapBridgeFactory: FakeMapBridge.new,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(service.routeRequests, [record.id]);
      expect(find.byType(SavedRunMap), findsOneWidget);
      final map = tester.widget<RunMap>(find.byType(RunMap));
      expect(map.segments, hasLength(2));
      expect(map.segments.map((line) => line.length), [2, 2]);
      expect(map.endpoints, isTrue);
      expect(map.controller.command['type'], 'fit');
      expect(
        map.controller.command['points'],
        route.segments
            .expand((s) => s)
            .map((p) => [p.latitude, p.longitude])
            .toList(),
      );
      final revision = map.controller.command['revision'] as int;
      await tester.drag(find.byType(RunMap), const Offset(40, 30));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('전체 경로 보기'));
      await tester.pumpAndSettle();
      expect(map.controller.command['revision'], greaterThan(revision));
      expect(map.controller.command['type'], 'fit');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('서버 경로 조회 실패 후 재시도합니다', (tester) async {
    final service = FakeRunRecordService()..routeFailure = StateError('연결 실패');
    final controller = RunHistoryController(service, outbox: FakeRunOutbox());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RunRecordDetailScreen(
          record: record,
          controller: controller,
          mapBridgeFactory: FakeMapBridge.new,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('경로를 불러오지 못했습니다.'), findsOneWidget);
    service.routeFailure = null;
    service.routes[record.id] = route;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.byType(SavedRunMap), findsOneWidget);
    expect(service.routeRequests, hasLength(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('전송 대기 경로는 오프라인에서도 서버 조회 없이 표시합니다', (tester) async {
    final service = FakeRunRecordService()..routeFailure = StateError('오프라인');
    final controller = RunHistoryController(service, outbox: FakeRunOutbox());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RunRecordDetailScreen(
          record: RunRecord.pending(summary),
          controller: controller,
          mapBridgeFactory: FakeMapBridge.new,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SavedRunMap), findsOneWidget);
    expect(service.routeRequests, isEmpty);
    service.isCurrentOwner = false;
    controller.notifyListeners();
    await tester.pump();
    expect(find.byType(SavedRunMap), findsNothing);
    expect(find.text('로그인 상태를 확인해 주세요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('좌표 하나만 있는 정지 기록도 지도를 표시합니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SavedRunMap(
            route: RunRoute([
              [const LatLng(37.56, 126.97)],
            ]),
            mapBridgeFactory: FakeMapBridge.new,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<RunMap>(find.byType(RunMap));
    expect(map.segments.single, hasLength(1));
    expect(map.endpoints, isTrue);
    expect(map.controller.command['type'], 'fit');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
