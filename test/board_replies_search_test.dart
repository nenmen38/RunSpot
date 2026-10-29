import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/board_comments_controller.dart';
import 'package:runquest/features/board/board_screen.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:runquest/features/board/widgets/board_post_tile.dart';
import 'package:runquest/features/notifications/models/app_notification.dart';
import 'package:runquest/shared/theme/app_colors.dart';

import 'support/board_fakes.dart';

Widget boardApp(FakeBoardService service) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(18),
      child: BoardScreen(
        service: service,
        photoService: FakeBoardPhotoService(),
      ),
    ),
  ),
);

void main() {
  test('게시글·댓글은 작성한 날짜와 시각으로 표시합니다', () {
    expect(
      formatBoardDateTime(DateTime(2026, 10, 29, 9, 5)),
      '2026.10.29 09:05',
    );
    expect(formatBoardDateTime(DateTime(2026, 1, 3, 23, 41)), '2026.1.3 23:41');
  });

  test('답글은 원댓글 바로 아래에 묶고 답글에 답하면 원댓글로 보냅니다', () async {
    final service = FakeBoardService()
      ..commentRows = [
        commentJson('a'),
        commentJson('b'),
        commentJson('r1', parentId: 'a'),
        commentJson('orphan', parentId: 'gone'),
      ];
    final controller = BoardCommentsController(service, 'p');
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(
      [
        for (final item in controller.threads)
          '${item.comment.id}:${item.isReply}',
      ],
      ['a:false', 'r1:true', 'b:false'],
    );
    final reply = controller.threads[1].comment;
    expect(await controller.add('저도요', parent: reply), isNull);
    expect(service.commentParents.single, 'a');
  });

  test('답글 알림 문구를 보여줍니다', () {
    final item = AppNotification.fromJson({
      'id': 'n',
      'kind': 'reply',
      'post_id': 'p',
      'post_title': '한강 코스',
      'nickname': '러너',
      'comment': '저도요',
      'created_at': '2026-10-29T01:00:00Z',
      'read': false,
    });
    expect(item.kind, NotificationKind.reply);
    expect(item.message, '러너님이 내 댓글에 답글을 남겼어요: 저도요');
  });

  testWidgets('글 상세에서 댓글에 답글을 달고 취소할 수 있습니다', (tester) async {
    final service = FakeBoardService();
    service.onLoad = (_) =>
        Future.value(feed([postJson('1', board: 'national')]));
    service.commentRows = [commentJson('x'), commentJson('y', parentId: 'x')];
    await tester.pumpWidget(boardApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();
    expect(find.text('러너1 · 2026.10.26 ${_localTime()}'), findsOneWidget);
    await tester.tap(find.text('제목1'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.subdirectory_arrow_right), findsOneWidget);
    await tester.tap(find.text('답글 달기').first);
    await tester.pumpAndSettle();
    expect(find.text('러너x님에게 답글 작성 중'), findsOneWidget);
    await tester.tap(find.byTooltip('답글 취소'));
    await tester.pumpAndSettle();
    expect(find.text('러너x님에게 답글 작성 중'), findsNothing);

    await tester.tap(find.text('답글 달기').last);
    await tester.pumpAndSettle();
    expect(find.text('러너y님에게 답글 작성 중'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '좋아요 😀');
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pumpAndSettle();
    expect(service.addedComments.single.$2, '좋아요 😀');
    expect(service.commentParents.single, 'x');
    expect(find.text('러너y님에게 답글 작성 중'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('댓글c2'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('댓글c2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('검색어로 지금 게시판의 글을 찾고 검색을 닫으면 전체로 돌아갑니다', (tester) async {
    final service = FakeBoardService();
    service.onLoad = (call) => Future.value(
      feed(call.query == '없는말' ? const [] : [postJson('1', board: 'national')]),
    );
    await tester.pumpWidget(boardApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('board-search')), findsNothing);
    await tester.tap(find.byTooltip('검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('board-search')), ' 러닝 ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(service.loads.last.kind, BoardKind.national);
    expect(service.loads.last.query, '러닝');

    await tester.enterText(find.byKey(const ValueKey('board-search')), '없는말');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(find.text("'없는말'이(가) 들어간 글이 없어요."), findsOneWidget);

    await tester.tap(find.byTooltip('검색 닫기'));
    await tester.pumpAndSettle();
    expect(service.loads.last.query, isNull);
    expect(find.text('제목1'), findsOneWidget);

    // 게시판을 바꾸면 검색어를 지웁니다.
    await tester.tap(find.byTooltip('검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('board-search')), '러닝');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('동네'));
    await tester.pumpAndSettle();
    expect(service.loads.last.kind, BoardKind.local);
    expect(service.loads.last.query, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('조건 선택은 왼쪽에 검색 버튼은 오른쪽에 있습니다', (tester) async {
    final service = FakeBoardService();
    await tester.pumpWidget(boardApp(service));
    await tester.pumpAndSettle();
    final search = tester.getCenter(find.byTooltip('검색'));
    final all = tester.getCenter(find.text('전체'));
    expect(search.dx, greaterThan(all.dx));
    expect((search.dy - all.dy).abs(), lessThan(8));
    await tester.tap(find.text('러닝 대회'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('검색'), findsOneWidget);
  });

  testWidgets('댓글·답글 오른쪽 하트를 누르면 빨간 하트로 바뀝니다', (tester) async {
    final service = FakeBoardService();
    service.onLoad = (_) =>
        Future.value(feed([postJson('1', board: 'national')]));
    service.commentRows = [commentJson('x'), commentJson('y', parentId: 'x')];
    await tester.pumpWidget(boardApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제목1'));
    await tester.pumpAndSettle();

    final hearts = find.byTooltip('댓글 좋아요');
    expect(hearts, findsNWidgets(2));
    // 하트는 댓글 내용보다 오른쪽 끝에 있습니다.
    expect(
      tester.getCenter(hearts.last).dx,
      greaterThan(tester.getCenter(find.text('댓글y')).dx),
    );
    await tester.tap(hearts.last);
    await tester.pumpAndSettle();
    expect(service.commentLikes.single, ('y', true));
    final filled = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('댓글 좋아요 취소'),
        matching: find.byType(Icon),
      ),
    );
    expect(filled.icon, Icons.favorite);
    expect(filled.color, AppColors.red);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('댓글 좋아요 취소'));
    await tester.pumpAndSettle();
    expect(service.commentLikes.last, ('y', false));
    expect(find.byTooltip('댓글 좋아요'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

// 테스트 글은 2026-10-26T01:00Z에 작성되었으므로 실행 환경의 현지 시각으로 바꿉니다.
String _localTime() {
  final time = DateTime.parse('2026-10-26T01:00:00Z').toLocal();
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}
