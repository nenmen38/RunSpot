import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/monetization/cosmetics.dart';
import 'package:runquest/features/titles/badge_directory.dart';
import 'package:runquest/features/titles/title_service.dart';
import 'package:runquest/features/titles/titles_card.dart';

class _Titles implements TitleService {
  RunnerTitle? selected;
  final userCalls = <List<String>>[];

  @override
  bool get isCurrentOwner => true;

  TitlesState get _state => TitlesState.fromJson({
    'selected': selected?.code,
    'titles': [
      {'code': 'ten_k', 'progress': 10000, 'goal': 10000, 'earned': true},
      {'code': 'half', 'progress': 10200, 'goal': 21097, 'earned': false},
      {'code': 'dawn', 'progress': 3, 'goal': 10, 'earned': false},
    ],
  });

  @override
  Future<TitlesState> load() async => _state;

  @override
  Future<TitlesState> select(RunnerTitle? title) async {
    selected = title;
    return _state;
  }

  @override
  Future<Map<String, UserBadge>> userBadges(List<String> userIds) async {
    userCalls.add(userIds);
    return {
      'friend': const UserBadge(
        title: RunnerTitle.tenK,
        titleStyle: CosmeticItem.titleCrown,
        chatBubble: CosmeticItem.bubbleMint,
      ),
    };
  }

  @override
  Future<Map<String, UserBadge>> postBadges(List<String> postIds) async => {};
}

void main() {
  testWidgets('얻은 칭호만 달 수 있고 못 얻은 칭호는 진행을 보여줍니다', (tester) async {
    final service = _Titles();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: TitlesCard(service: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('10.2 / 21.1km'), findsOneWidget);
    expect(find.text('3 / 10회'), findsOneWidget);
    // 얻은 칭호(10K 클럽)에만 '달기' 버튼이 있습니다.
    expect(find.text('달기'), findsOneWidget);
    await tester.tap(find.text('달기'));
    await tester.pumpAndSettle();
    expect(service.selected, RunnerTitle.tenK);
    expect(find.text('떼기'), findsOneWidget);
    expect(find.bySemanticsLabel('칭호 10K 클럽'), findsOneWidget);
    await tester.tap(find.text('떼기'));
    await tester.pumpAndSettle();
    expect(service.selected, isNull);
  });

  testWidgets('화면에 나온 사람들의 칭호를 한 번에 불러와 이름 옆에 붙입니다', (tester) async {
    final service = _Titles();
    BadgeDirectory.instance.bind(service);
    addTearDown(BadgeDirectory.instance.unbind);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Row(
                children: [
                  Text('친구'),
                  UserTitle(userId: 'friend'),
                ],
              ),
              Row(
                children: [
                  Text('다른 사람'),
                  UserTitle(userId: 'other'),
                ],
              ),
              Row(
                children: [
                  Text('친구 또'),
                  UserTitle(userId: 'friend'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 세 번 그렸지만 서버에는 두 사람을 한 번에 물어봅니다.
    expect(service.userCalls, hasLength(1));
    expect(service.userCalls.single.toSet(), {'friend', 'other'});
    expect(find.text('10K 클럽'), findsNWidgets(2));
    expect(find.byIcon(Icons.workspace_premium), findsNWidgets(2));
    expect(
      BadgeDirectory.instance.user('friend')?.chatBubble,
      CosmeticItem.bubbleMint,
    );
  });
}
