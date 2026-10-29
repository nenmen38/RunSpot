import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/board_compose_screen.dart';
import 'package:runquest/features/board/board_controller.dart';
import 'package:runquest/features/board/board_screen.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:runquest/features/board/widgets/board_theme.dart';

import 'support/board_fakes.dart';

Widget enlarged(Widget child) => MaterialApp(
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: const TextScaler.linear(2)),
    child: page!,
  ),
  home: child,
);

void main() {
  testWidgets('작은 화면과 두 배 글자에서도 목록 필터와 상세 댓글을 사용할 수 있습니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeBoardService();
    service.onLoad = (call) =>
        Future.value(feed([postJson('1', board: call.kind.code)]));
    service.commentRows = [commentJson('other')];
    await tester.pumpWidget(
      enlarged(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: BoardScreen(service: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('말머리 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<int>, '꿀 정보'));
    await tester.pumpAndSettle();
    expect(service.loads.last.topic, BoardTopic.tip);
    await tester.ensureVisible(find.text('제목1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제목1'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('답글 달기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('답글 달기'));
    await tester.pumpAndSettle();
    expect(find.text('러너other님에게 답글 작성 중'), findsOneWidget);
    expect(find.byTooltip('댓글 등록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('확대 글자에서도 작성 내용을 유지하고 등록할 수 있습니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = FakeBoardService();
    final controller = BoardController(service)..kind = BoardKind.national;
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      enlarged(BoardComposeScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('꿀 정보'));
    await tester.enterText(find.byKey(const ValueKey('title')), '좋은 러닝 코스');
    await tester.enterText(
      find.byKey(const ValueKey('body')),
      '길이 밝고 넓어서 달리기 좋아요.',
    );
    tester.testTextInput.hide();
    await tester.ensureVisible(find.text('등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    expect(service.created.single.title, '좋은 러닝 코스');
    expect(tester.takeException(), isNull);
  });

  test('게시판 글자·강조·오류 색은 밝은 배경에서 대비 기준을 충족합니다', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final color in [
      BoardStyle.ink,
      BoardStyle.secondary,
      BoardStyle.accent,
      BoardStyle.error,
    ]) {
      expect(contrast(color, Colors.white), greaterThanOrEqualTo(4.5));
    }
    expect(
      contrast(BoardStyle.secondary, BoardStyle.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(BoardStyle.accent, BoardStyle.accentSoft),
      greaterThanOrEqualTo(4.5),
    );
  });
}
