import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/board_compose_screen.dart';
import 'package:runquest/features/board/board_controller.dart';
import 'package:runquest/features/board/board_post_screen.dart';
import 'package:runquest/features/board/board_screen.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/run_history_screen.dart';
import 'package:runquest/features/settings/settings_screen.dart';

import 'support/board_fakes.dart';
import 'support/run_history_fakes.dart';

void main() {
  RunRecord record() => RunRecord(
    id: 'record',
    clientRunId: 'client',
    startedAt: DateTime.utc(2026, 10, 26),
    endedAt: DateTime.utc(2026, 10, 26, 1),
    distanceMeters: 2000,
    durationSeconds: 600,
  );

  test('숨김은 원본을 보존하고 복원하면 같은 기록이 다시 보입니다', () async {
    final service = FakeRunRecordService()..records.add(record());
    final controller = RunHistoryController(service, outbox: FakeRunOutbox());
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.setHidden(controller.visibleRecords.single, true);
    expect(controller.visibleRecords, isEmpty);
    expect(controller.hiddenRecords.single.distanceMeters, 2000);
    expect(service.records, hasLength(1));
    await controller.setHidden(controller.hiddenRecords.single, false);
    expect(controller.visibleRecords.single.clientRunId, 'client');
    expect(controller.hiddenRecords, isEmpty);
    service.isCurrentOwner = false;
    await expectLater(controller.setHidden(record(), true), throwsA(anything));
    expect(service.records.single.hidden, isFalse);
  });

  testWidgets('상세에서 숨긴 뒤 숨긴 목록에서 복원합니다', (tester) async {
    final service = FakeRunRecordService()..records.add(record());
    final controller = RunHistoryController(service, outbox: FakeRunOutbox());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: RunHistoryScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.00 km'));
    await tester.pumpAndSettle();
    // 핵심 수치는 경로보다 앞에 배치합니다.
    expect(
      tester.getTopLeft(find.text('2.00 km')).dy,
      lessThan(tester.getTopLeft(find.text('이동 경로')).dy),
    );
    await tester.tap(find.byTooltip('기록 숨기기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('숨기기'));
    await tester.pumpAndSettle();
    expect(controller.visibleRecords, isEmpty);
    await tester.tap(find.byTooltip('숨긴 기록 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2.00 km'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('기록 복원'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('복원'));
    await tester.pumpAndSettle();
    expect(controller.visibleRecords, hasLength(1));
    expect(controller.hiddenRecords, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('내 글 수정은 기존 내용을 채우고 수정 요청을 전송합니다', (tester) async {
    final service = FakeBoardService();
    final controller = BoardController(service);
    addTearDown(controller.dispose);
    await controller.refresh();
    final post = BoardPost.fromJson(postJson('mine', isMine: true));
    await tester.pumpWidget(
      MaterialApp(
        home: BoardComposeScreen(controller: controller, post: post),
      ),
    );
    expect(find.text('제목mine'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('title')), '수정한 제목');
    await tester.ensureVisible(find.text('수정 완료'));
    await tester.tap(find.text('수정 완료'));
    await tester.pumpAndSettle();
    expect(service.updated.single.title, '수정한 제목');
    expect(service.created, isEmpty);
  });

  testWidgets('다른 사용자 글은 사유 입력 후 신고하고 본인 글은 신고 메뉴가 없습니다', (tester) async {
    final service = FakeBoardService();
    final controller = BoardController(service);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: BoardPostScreen(
          controller: controller,
          post: BoardPost.fromJson(postJson('other')),
        ),
      ),
    );
    await tester.tap(find.byTooltip('게시글 메뉴'));
    await tester.pumpAndSettle();
    expect(find.text('수정'), findsNothing);
    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '스팸·광고'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '광고성 글',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '신고'));
    await tester.pumpAndSettle();
    expect(service.reported, ['other:스팸·광고\n광고성 글']);
    expect(find.text('신고가 접수되었습니다.'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: BoardPostScreen(
          controller: controller,
          post: BoardPost.fromJson(postJson('mine', isMine: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('게시글 메뉴'));
    await tester.pumpAndSettle();
    expect(find.text('신고'), findsNothing);
    expect(find.text('수정'), findsOneWidget);
  });

  testWidgets('관리 메뉴는 역할 확인 후에만 표시하고 실패하면 숨깁니다', (tester) async {
    Future<void> show(Future<bool> access) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            adminBuilder: (_) => const SizedBox(),
            isCurrentOwner: () => true,
            managementAccess: access,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show(Future.value(false));
    expect(find.text('관리'), findsNothing);
    await show(Future.value(true));
    expect(find.text('관리'), findsOneWidget);
    final failure = Completer<bool>();
    await show(failure.future);
    failure.completeError(StateError('역할 조회 실패'));
    await tester.pumpAndSettle();
    expect(find.text('관리'), findsNothing);
  });

  testWidgets('빈 게시판에서도 당겨서 새로고침합니다', (tester) async {
    final service = FakeBoardService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BoardScreen(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    final before = service.loads.length;
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(service.loads.length, greaterThan(before));
  });
}
