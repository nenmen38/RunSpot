import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:runquest/features/board/board_controller.dart';
import 'package:runquest/features/board/board_post_screen.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:runquest/features/board/widgets/board_report_dialog.dart';

import 'support/board_fakes.dart';

void main() {
  testWidgets('신고 사유 선택과 기타 상세 입력을 확인합니다', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('열기'),
              onPressed: () async {
                submitted = await showDialog<String>(
                  context: context,
                  builder: (_) => const BoardReportDialog(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, '신고'));
    expect(button().onPressed, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, '기타'));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '개인정보가 포함돼 있어요.');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '신고'));
    await tester.pumpAndSettle();
    expect(submitted, '기타\n개인정보가 포함돼 있어요.');
  });

  testWidgets('댓글 메뉴에서 사유만 골라도 신고할 수 있고 본인 댓글은 제외합니다', (tester) async {
    final service = FakeBoardService()
      ..commentRows = [commentJson('other'), commentJson('mine', isMine: true)];
    final controller = BoardController(service);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: BoardPostScreen(
          controller: controller,
          post: BoardPost.fromJson(postJson('post')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('댓글 메뉴'), findsOneWidget);
    await tester.tap(find.byTooltip('댓글 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고'));
    await tester.pumpAndSettle();
    expect(find.text('댓글 신고'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '욕설·비방'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '신고'));
    await tester.pumpAndSettle();
    expect(service.reportedComments, ['other:욕설·비방']);
    expect(find.text('신고가 접수되었습니다.'), findsOneWidget);
  });

  testWidgets('서버가 거절한 댓글은 입력한 내용을 유지합니다', (tester) async {
    final service = FakeBoardService()
      ..commentError = const PostgrestException(
        message: '욕설·비방 표현을 수정한 뒤 다시 등록해 주세요.',
        code: '22023',
      );
    final controller = BoardController(service);
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: BoardPostScreen(
          controller: controller,
          post: BoardPost.fromJson(postJson('post')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '수정할 댓글 내용');
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pumpAndSettle();
    expect(find.text('욕설·비방 표현을 수정한 뒤 다시 등록해 주세요.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '수정할 댓글 내용',
    );
    expect(service.commentRows, isEmpty);
  });
}
