import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/run_history_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/run_history_fakes.dart';

RunSummary summary(String id) => RunSummary(
  clientRunId: id,
  startedAt: DateTime.utc(2026, 10, 9, 6),
  endedAt: DateTime.utc(2026, 10, 9, 7),
  distanceMeters: 5000.123,
  duration: const Duration(minutes: 25, microseconds: 456),
);

void main() {
  late FakeRunRecordService service;
  late FakeRunOutbox outbox;
  late RunHistoryController controller;
  void reset() {
    service = FakeRunRecordService();
    outbox = FakeRunOutbox();
    controller = RunHistoryController(service, outbox: outbox);
  }

  setUp(reset);
  tearDown(() {
    controller.dispose();
  });

  test('기기 저장 실패 시 서버 호출을 하지 않습니다', () async {
    outbox.putFailure = const RunOutboxException('저장 공간 부족');
    await expectLater(
      controller.save(summary('run')),
      throwsA(isA<RunOutboxException>()),
    );
    expect(service.attempts, isEmpty);
    expect(controller.pendingRecords, isEmpty);
  });

  test('서버 저장 뒤 응답이 끊겨도 같은 식별자를 재전송합니다', () async {
    service.responseFailure = const SocketException('응답 중단');
    final result = await controller.save(summary('run'));
    expect(result.pendingSync, isTrue);
    expect(service.records, hasLength(1));
    expect(outbox.rows, hasLength(1));
    controller.records = [...service.records];
    expect(controller.visibleRecords, hasLength(1));
    expect(controller.visibleRecords.single.pendingSync, isTrue);
    await controller.syncPending();
    expect(service.records, hasLength(1));
    expect(service.attempts.map((row) => row.clientRunId), ['run', 'run']);
    expect(outbox.rows, isEmpty);
  });

  test('서버 성공 후 기기 삭제가 실패해도 원본을 잃지 않습니다', () async {
    outbox.removeFailure = const RunOutboxException('디스크 실패');
    expect((await controller.save(summary('run'))).pendingSync, isTrue);
    expect(service.records, hasLength(1));
    expect(outbox.rows, hasLength(1));
    outbox.removeFailure = null;
    await controller.syncPending();
    expect(service.records, hasLength(1));
    expect(controller.syncError, isNull);
    expect(outbox.rows, isEmpty);
  });

  test('자동 복구가 늦어도 새 기록은 서버 응답 전에 디스크에 저장됩니다', () async {
    await outbox.put(summary('old'));
    service.pendingSave = Completer<void>();
    final recovery = controller.syncPending();
    await Future<void>.delayed(Duration.zero);
    final save = controller.save(summary('new'));
    await Future<void>.delayed(Duration.zero);
    expect(outbox.rows.keys, containsAll(['old', 'new']));
    expect(service.attempts.map((row) => row.clientRunId), ['old']);
    service.pendingSave!.complete();
    await recovery;
    await save;
    expect(service.records, hasLength(2));
    expect(outbox.rows, isEmpty);
  });

  test('동시에 요청한 복구는 하나의 전송만 실행합니다', () async {
    await outbox.put(summary('run'));
    service.pendingSave = Completer<void>();
    final first = controller.syncPending();
    final second = controller.syncPending();
    await Future<void>.delayed(Duration.zero);
    expect(service.attempts, hasLength(1));
    service.pendingSave!.complete();
    await first;
    await second;
    expect(service.records, hasLength(1));
  });

  test('전송 중 계정이 바뀌면 원본을 보관하고 추가 요청을 중단합니다', () async {
    service.pendingSave = Completer<void>();
    final save = controller.save(summary('run'));
    await Future<void>.delayed(Duration.zero);
    service.isCurrentOwner = false;
    service.pendingSave!.complete();
    expect((await save).pendingSync, isTrue);
    expect(outbox.rows, hasLength(1));
    await controller.syncPending();
    expect(service.attempts, hasLength(1));
    await expectLater(
      controller.save(summary('other')),
      throwsA(isA<AuthException>()),
    );
    controller.dispose();
    expect(controller.visibleRecords, isEmpty);
    outbox = FakeRunOutbox(rows: outbox.rows);
    controller = RunHistoryController(service, outbox: outbox);
    service.isCurrentOwner = true;
    await controller.syncPending();
    expect(service.records, hasLength(1));
    expect(outbox.rows, isEmpty);
  });

  test('계정이 다른 저장소를 연결하지 않습니다', () {
    expect(
      () => RunHistoryController(
        service,
        outbox: FakeRunOutbox(ownerId: 'other'),
      ),
      throwsArgumentError,
    );
  });

  test('백그라운드에서 완료한 기록도 기기에 보관하고 복귀 시 전송합니다', () async {
    await controller.setActive(false);
    final result = await controller.save(summary('run'));
    expect(result.pendingSync, isTrue);
    expect(controller.pendingRecords, hasLength(1));
    expect(service.attempts, isEmpty);
    expect(outbox.rows, hasLength(1));
    await controller.setActive(true);
    expect(service.records, hasLength(1));
    expect(outbox.rows, isEmpty);
  });

  test('기기 보관 목록 조회 실패 시 원본을 유지하고 복구를 다시 시도합니다', () async {
    await outbox.put(summary('run'));
    outbox.listFailure = const RunOutboxException('디스크 읽기 실패');
    await controller.syncPending();
    expect(controller.syncError, '디스크 읽기 실패');
    expect(service.attempts, isEmpty);
    expect(outbox.rows, hasLength(1));
    outbox.listFailure = null;
    await controller.syncPending();
    expect(controller.syncError, isNull);
    expect(service.records, hasLength(1));
    expect(outbox.rows, isEmpty);
  });

  test('복구 중 종료해도 대기 기록을 삭제하거나 다시 전송하지 않습니다', () async {
    await outbox.put(summary('run'));
    service.pendingSave = Completer<void>();
    final recovery = controller.syncPending();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    service.pendingSave!.complete();
    await recovery;
    expect(outbox.rows, hasLength(1));
    expect(controller.visibleRecords, isEmpty);
    await controller.syncPending();
    expect(service.attempts, hasLength(1));
    controller = RunHistoryController(
      service,
      outbox: FakeRunOutbox(rows: outbox.rows),
    );
  });

  testWidgets('연결 실패 후 자동 재시도하고 백그라운드에서는 중단합니다', (tester) async {
    controller.dispose();
    reset();
    service.saveFailure = const SocketException('오프라인');
    await outbox.put(summary('run'));
    await controller.setActive(true);
    expect(service.attempts, hasLength(1));
    await tester.pump(const Duration(seconds: 30));
    expect(service.attempts, hasLength(2));
    await tester.pump(const Duration(seconds: 59));
    expect(service.attempts, hasLength(2));
    await controller.setActive(false);
    await tester.pump(const Duration(minutes: 10));
    expect(service.attempts, hasLength(2));
    service.saveFailure = null;
    await controller.setActive(true);
    expect(service.attempts, hasLength(3));
    expect(outbox.rows, isEmpty);
    await tester.pump(const Duration(minutes: 10));
    expect(service.attempts, hasLength(3));
  });

  testWidgets('서버에서 거부한 기록은 원본을 유지하고 자동 반복 요청하지 않습니다', (tester) async {
    controller.dispose();
    reset();
    service.saveFailure = const PostgrestException(
      message: '잘못된 기록',
      code: '22023',
    );
    await outbox.put(summary('run'));
    await controller.setActive(true);
    await tester.pump(const Duration(minutes: 10));
    expect(service.attempts, hasLength(1));
    expect(outbox.rows, hasLength(1));
    expect(controller.syncError, '잘못된 기록');
    service.saveFailure = null;
    await controller.syncPending();
    expect(outbox.rows, isEmpty);
  });

  testWidgets('요청 제한 시간이 지나도 기록을 보관하고 재시도합니다', (tester) async {
    controller.dispose();
    reset();
    await outbox.put(summary('run'));
    service.pendingSave = Completer<void>();
    final recovery = controller.setActive(true);
    await tester.pump();
    await tester.pump(RunHistoryController.requestTimeout);
    await recovery;
    expect(outbox.rows, hasLength(1));
    expect(controller.syncError, isNotNull);
    service.pendingSave!.complete();
    await tester.pump();
    await controller.syncPending();
    expect(service.records, hasLength(1));
    expect(outbox.rows, isEmpty);
  });

  testWidgets('좁은 화면에서도 오프라인 대기 기록과 상세를 표시하고 재전송합니다', (tester) async {
    controller.dispose();
    reset();
    service.saveFailure = const SocketException('오프라인');
    service.listFailure = const SocketException('오프라인');
    await outbox.put(summary('run'));
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: RunHistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('서버 저장 대기'), findsOneWidget);
    expect(find.text('5.00 km'), findsOneWidget);
    expect(find.text('저장 재시도'), findsOneWidget);
    await tester.tap(find.text('5.00 km'));
    await tester.pumpAndSettle();
    expect(find.text('서버 저장 대기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    service.saveFailure = null;
    service.listFailure = null;
    await tester.tap(find.text('저장 재시도'));
    await tester.pumpAndSettle();
    expect(find.text('서버 저장 대기'), findsNothing);
    expect(find.text('5.00 km'), findsOneWidget);
    expect(controller.visibleRecords, hasLength(1));
    expect(controller.visibleRecords.single, isA<RunRecord>());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
