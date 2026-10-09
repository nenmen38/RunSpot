import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/run_history_screen.dart';
import 'package:runquest/features/run_history/widgets/run_record_details.dart';

import 'support/run_history_fakes.dart';

RunRecord record(int index, {int distance = 5000, int seconds = 1500}) =>
    RunRecord(
      id: '$index',
      clientRunId: '$index',
      startedAt: DateTime.utc(2026, 10, 8, 6).subtract(Duration(days: index)),
      endedAt: DateTime.utc(2026, 10, 8, 7).subtract(Duration(days: index)),
      distanceMeters: distance,
      durationSeconds: seconds,
    );

void main() {
  test('평균 페이스와 이동하지 않은 기록을 표시합니다', () {
    expect(record(0).paceSeconds, 300);
    expect(formatRunPace(record(0)), '5:00 /km');
    expect(formatRunPace(record(0, distance: 0)), '--');
    expect(formatRunPace(record(0, seconds: 0)), '--');
  });

  test('기록을 20개씩 조회하고 새로고침은 처음부터 조회합니다', () async {
    final service = FakeRunRecordService()
      ..records.addAll(List.generate(25, record));
    final controller = RunHistoryController(service, outbox: FakeRunOutbox());
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.records, hasLength(20));
    expect(controller.hasMore, isTrue);
    await controller.loadMore();
    expect(controller.records, hasLength(25));
    expect(controller.hasMore, isFalse);
    expect(service.offsets, [0, 20]);
    await controller.refresh();
    expect(controller.records, hasLength(20));
    expect(service.offsets.last, 0);
  });

  test('새로고침 실패 시 기존 기록을 유지하고 첫 페이지를 재시도합니다', () async {
    final service = FakeRunRecordService()
      ..records.addAll(List.generate(25, record));
    final controller = RunHistoryController(service, outbox: FakeRunOutbox());
    addTearDown(controller.dispose);
    await controller.refresh();
    service.listFailure = StateError('연결 실패');
    await controller.refresh();
    expect(controller.records, hasLength(20));
    expect(controller.error, isNotNull);
    service.listFailure = null;
    await controller.retry();
    expect(service.offsets.last, 0);
    expect(controller.error, isNull);
    service.listFailure = StateError('연결 실패');
    await controller.loadMore();
    service.listFailure = null;
    await controller.retry();
    expect(service.offsets.last, 20);
    expect(controller.records, hasLength(25));
  });

  testWidgets('목록 오류를 재시도하고 기록 상세를 엽니다', (tester) async {
    final service = FakeRunRecordService()..listFailure = StateError('연결 실패');
    final controller = RunHistoryController(service, outbox: FakeRunOutbox());
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: RunHistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('다시 시도'), findsOneWidget);
    service.listFailure = null;
    service.records.add(record(0));
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('5.00 km'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('5:00 /km'), findsOneWidget);
    await tester.tap(find.text('5.00 km'));
    await tester.pumpAndSettle();
    expect(find.text('러닝 기록'), findsOneWidget);
    expect(find.text('평균 페이스'), findsOneWidget);
    expect(find.text('저장된 경로가 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('기록이 없으면 빈 목록을 표시합니다', (tester) async {
    final controller = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RunHistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('아직 러닝 기록이 없습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
