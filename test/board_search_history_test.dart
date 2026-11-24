import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/board_screen.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:runquest/shared/search_history.dart';

import 'support/board_fakes.dart';

void main() {
  testWidgets('게시판 검색창을 눌러야 최근 검색어가 뜨고, 게시판 종류마다 따로 남습니다', (tester) async {
    final disk = <String, String>{};
    final service = FakeBoardService();
    service.onLoad = (_) =>
        Future.value(feed([postJson('1', board: 'national')]));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: BoardScreen(
              service: service,
              photoService: FakeBoardPhotoService(),
              searchHistory: (scope) => SearchHistory(
                scope: scope,
                owner: () => 'me',
                read: (key) async => disk[key],
                write: (key, value) async =>
                    value == null ? disk.remove(key) : disk[key] = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('board-search'));
    final panel = find.byKey(const ValueKey('board-recent-searches'));

    // 검색 버튼으로 검색창을 열기만 해서는 최근 검색어가 뜨지 않습니다.
    await tester.tap(find.byTooltip('검색'));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    // 검색창을 누르면 펼쳐집니다.
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(find.text('최근 검색어 내역이 없습니다.'), findsOneWidget);

    for (final word in ['한강', '야간 러닝']) {
      await tester.enterText(field, word);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }
    // 검색하면 닫히고, 지운 뒤 다시 누르면 최신순으로 보입니다.
    expect(panel, findsNothing);
    await tester.enterText(field, '');
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-야간 러닝')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-한강')), findsOneWidget);

    // 하나만 지우고, 남은 검색어를 누르면 다시 검색합니다.
    await tester.tap(find.byTooltip('야간 러닝 검색어 삭제'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-야간 러닝')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('recent-한강')));
    await tester.pumpAndSettle();
    expect(service.loads.last.query, '한강');
    expect(panel, findsNothing);

    // 크루 홍보 게시판은 따로 기록합니다.
    await tester.tap(find.text(BoardKind.crew.label));
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('최근 검색어 내역이 없습니다.'), findsOneWidget);
  });
}
