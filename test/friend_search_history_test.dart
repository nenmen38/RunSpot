import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/social/friend_controller.dart';
import 'package:runquest/shared/search_history.dart';
import 'package:runquest/features/social/widgets/friend_search.dart';

import 'support/friend_fakes.dart';

SearchHistory memoryHistory(Map<String, String> disk, {String owner = 'me'}) =>
    SearchHistory(
      scope: 'friend',
      owner: () => owner,
      read: (key) async => disk[key],
      write: (key, value) async =>
          value == null ? disk.remove(key) : disk[key] = value,
    );

void main() {
  test('최근 검색어는 최신순으로 중복 없이 10개까지, 계정마다 따로 저장합니다', () async {
    final disk = <String, String>{};
    final history = memoryHistory(disk);
    await history.load();
    for (var i = 0; i < 12; i++) {
      await history.add('러너$i', at: DateTime(2026, 11, 24, 9, i));
    }
    await history.add('러너5');
    expect(history.items.map((e) => e.query).take(3), ['러너5', '러너11', '러너10']);
    expect(history.items, hasLength(10));

    // 다시 열어도 그대로 남고, 다른 계정에는 보이지 않습니다.
    final again = memoryHistory(disk);
    await again.load();
    expect(again.items.first.query, '러너5');
    final other = memoryHistory(disk, owner: 'other');
    await other.load();
    expect(other.items, isEmpty);

    // 자동저장을 끄면 새 검색어를 저장하지 않습니다.
    await again.setEnabled(false);
    await again.add('새검색');
    expect(again.items.any((e) => e.query == '새검색'), isFalse);
    final reopened = memoryHistory(disk);
    await reopened.load();
    expect(reopened.enabled, isFalse);
  });

  testWidgets('검색하면 최근 검색어에 남고, 하나씩·전체 지우고 자동저장을 끄고 켭니다', (tester) async {
    final controller = FriendController(FakeFriendService());
    addTearDown(controller.dispose);
    // 친구 목록을 먼저 불러와야 검색할 수 있습니다.
    await controller.refresh();
    final history = memoryHistory({});
    await history.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendSearch(controller: controller, history: history),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('최근 검색어'), findsOneWidget);
    expect(find.text('최근 검색어 내역이 없습니다.'), findsOneWidget);

    for (final nickname in ['러너1', '러너2']) {
      await tester.enterText(find.byType(TextField), nickname);
      await tester.tap(find.byTooltip('친구 검색'));
      await tester.pumpAndSettle();
    }
    // 입력칸을 비우면 최근 검색어가 최신순으로 보입니다.
    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-러너2')), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-러너1')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('recent-러너2'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('recent-러너1'))).dy),
    );

    // 하나만 지웁니다.
    await tester.tap(find.byTooltip('러너2 검색어 삭제'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recent-러너2')), findsNothing);
    expect(history.items.map((e) => e.query), ['러너1']);

    // 최근 검색어를 누르면 다시 검색합니다.
    await tester.tap(find.byKey(const ValueKey('recent-러너1')));
    await tester.pumpAndSettle();
    expect(controller.searched, isTrue);
    expect(find.text('최근 검색어'), findsNothing);
    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pumpAndSettle();

    // 전체 삭제는 한 번 더 묻습니다.
    await tester.tap(find.text('전체 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(history.items, isEmpty);

    // 자동저장을 끄면 안내만 보이고, 켜면 다시 저장합니다.
    await tester.tap(find.text('자동저장 끄기'));
    await tester.pumpAndSettle();
    expect(find.text('검색어 저장 기능이 꺼져 있습니다.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '러너3');
    await tester.tap(find.byTooltip('친구 검색'));
    await tester.pumpAndSettle();
    expect(history.items, isEmpty);
    await tester.tap(find.byTooltip('검색어 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자동저장 켜기'));
    await tester.pumpAndSettle();
    expect(history.enabled, isTrue);
  });
}
