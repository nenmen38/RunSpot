import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/crew/crew_controller.dart';
import 'package:runquest/features/crew/models/crew.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/profile_cosmetics.dart';
import 'package:runquest/features/social/models/friend_entry.dart';
import 'package:runquest/features/social/social_screen.dart';

import 'support/crew_fakes.dart';
import 'support/friend_fakes.dart';
import 'support/statistics_fakes.dart';
import 'support/wallet_fakes.dart';

Widget itemPage(WalletController wallet, CrewController crew) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(disableAnimations: true, size: Size(400, 900)),
    child: Scaffold(
      body: ProfileCosmetics.store(wallet: wallet, crew: crew),
    ),
  ),
);

Future<void> showSocial(
  WidgetTester tester,
  FakeFriendService friends,
  CrewController crew,
) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SocialScreen(
            rankingService: FakeRankingService(),
            friendService: friends,
            crewController: crew,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('크루 생성권은 약 7,000원(640코인)이고 아이콘은 다섯 가지입니다', () {
    expect(Wallet.crewTicketDefaultPrice, 640);
    // 1,100원 = 100코인 기준입니다.
    expect(Wallet.crewTicketDefaultPrice * 11, 7040);
    expect(CrewIcon.values.map((icon) => icon.code), [
      'bolt',
      'flame',
      'mountain',
      'wave',
      'star',
    ]);
    expect(CrewIcon.fromCode('wave'), CrewIcon.wave);
  });

  testWidgets('상점에서 크루 생성권을 사고 보관함에서 사용해 크루를 만듭니다', (tester) async {
    final walletService = FakeWalletService()..coins = 1000;
    final wallet = WalletController(walletService);
    final crewService = FakeCrewService(wallet: walletService);
    final crew = CrewController(crewService);
    addTearDown(wallet.dispose);
    addTearDown(crew.dispose);
    await wallet.refresh();
    await crew.refresh();
    await tester.pumpWidget(itemPage(wallet, crew));
    await tester.pumpAndSettle();
    // 생성권이 없으면 보관함에 크루 칸이 없습니다.
    expect(find.byKey(const ValueKey('inventory-crew-ticket')), findsNothing);

    await tester.tap(find.text('상점'));
    await tester.pumpAndSettle();
    final ticket = find.byKey(const ValueKey('shop-crew-ticket'));
    await tester.scrollUntilVisible(ticket, 200);
    expect(
      find.descendant(of: ticket, matching: find.textContaining('640코인')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: ticket, matching: find.text('구매')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '구매').last);
    await tester.pumpAndSettle();
    expect(walletService.calls, ['buy:crew_ticket']);
    expect(find.text('360'), findsOneWidget);
    expect(
      find.descendant(of: ticket, matching: find.text('보유 중')),
      findsOneWidget,
    );

    await tester.tap(find.text('보관함'));
    await tester.pumpAndSettle();
    expect(find.text('크루 생성권 ×1'), findsOneWidget);
    await tester.tap(find.text('사용하기'));
    await tester.pumpAndSettle();
    expect(find.text('크루 만들기'), findsWidgets);
    for (final icon in CrewIcon.values) {
      expect(find.bySemanticsLabel('크루 아이콘 ${icon.label}'), findsOneWidget);
    }

    // 이름과 아이콘이 없으면 만들지 않습니다.
    await tester.tap(find.widgetWithText(FilledButton, '크루 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('크루 이름은 2~20자로 입력해 주세요.'), findsOneWidget);
    expect(find.text('크루 아이콘을 골라 주세요.'), findsOneWidget);
    expect(crewService.calls, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('crew-name')), ' 새벽런 ');
    await tester.enterText(
      find.byKey(const ValueKey('crew-description')),
      '매일 아침 한강 5km',
    );
    await tester.tap(find.bySemanticsLabel('크루 아이콘 파도'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '크루 만들기'));
    await tester.pumpAndSettle();
    expect(crewService.calls, ['create:새벽런:매일 아침 한강 5km:wave']);
    expect(crew.crew!.name, '새벽런');
    expect(crew.crew!.icon, CrewIcon.wave);
    expect(find.textContaining('새벽런를 만들었어요'), findsOneWidget);
    // 생성권을 썼으므로 보관함의 크루 칸이 사라집니다.
    expect(find.byKey(const ValueKey('inventory-crew-ticket')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('크루 이름이 겹치면 창을 닫지 않고 이유를 보여줍니다', (tester) async {
    final walletService = FakeWalletService()..crewTickets = 1;
    final wallet = WalletController(walletService);
    final crew = CrewController(FakeCrewService(wallet: walletService));
    addTearDown(wallet.dispose);
    addTearDown(crew.dispose);
    await wallet.refresh();
    await crew.refresh();
    await tester.pumpWidget(itemPage(wallet, crew));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사용하기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('crew-name')), '이미있음');
    await tester.tap(find.bySemanticsLabel('크루 아이콘 별'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '크루 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('이미 쓰고 있는 크루 이름이에요.'), findsOneWidget);
    expect(crew.crew, isNull);
  });

  Finder menuOf(String userId) => find.descendant(
    of: find.byKey(ValueKey('friend-$userId')),
    matching: find.byTooltip('친구 관리'),
  );

  testWidgets('크루 초대는 친구 이름 옆 … 메뉴 안에 있고 크루장에게만 보입니다', (tester) async {
    final friends = FakeFriendService()
      ..entries = [
        friendEntry('2', FriendRelation.friend),
        friendEntry('3', FriendRelation.friend),
      ];
    final service = FakeCrewService()..crews = [FakeCrewService.crewJson()];
    final crew = CrewController(service);
    addTearDown(crew.dispose);
    await crew.refresh();
    await showSocial(tester, friends, crew);

    // 크루 탭은 친구 탭 바로 다음에 있습니다.
    final tabs = tester.widget<TabBar>(find.byType(TabBar)).tabs;
    expect((tabs[0] as Tab).text, '친구');
    expect(
      tester.getCenter(find.text('크루')).dx,
      greaterThan(tester.getCenter(find.text('친구')).dx),
    );
    // 친구 줄에는 따로 버튼이 없습니다.
    expect(find.widgetWithText(FilledButton, '크루원 초대하기'), findsNothing);
    expect(find.widgetWithText(FilledButton, '크루원 초대하기'), findsNothing);

    // 러너2는 이미 크루원이라 메뉴에 초대가 없습니다.
    await tester.tap(menuOf('2'));
    await tester.pumpAndSettle();
    expect(find.text('크루원 초대하기'), findsNothing);
    expect(find.text('친구 삭제'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(menuOf('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('크루원 초대하기'));
    await tester.pumpAndSettle();
    expect(service.calls, ['invite:3:crew-1']);
    expect(find.text('러너3님에게 새벽런 크루 초대를 보냈어요.'), findsOneWidget);
    // 이미 초대했으면 메뉴에 "크루 초대함"으로 보이고 누를 수 없습니다.
    await tester.tap(menuOf('3'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, '크루 초대함'),
          )
          .enabled,
      isFalse,
    );
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.text('크루'));
    await tester.pumpAndSettle();
    expect(find.text('새벽런'), findsOneWidget);
    expect(find.text('크루원 2/30명'), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-member-me')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-member-2')), findsOneWidget);
    // 크루원이 아닌 친구는 크루 탭에 나오지 않습니다.
    expect(find.byKey(const ValueKey('crew-member-3')), findsNothing);
    expect(find.text('크루장'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('내가 크루장인 크루가 여럿이면 초대할 크루를 고릅니다', (tester) async {
    final friends = FakeFriendService()
      ..entries = [friendEntry('3', FriendRelation.friend)];
    final service = FakeCrewService()
      ..crews = [
        FakeCrewService.crewJson(),
        FakeCrewService.crewJson(id: 'crew-2', name: '저녁런', icon: 'wave'),
      ];
    final crew = CrewController(service);
    addTearDown(crew.dispose);
    await crew.refresh();
    await showSocial(tester, friends, crew);
    await tester.tap(menuOf('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('크루원 초대하기'));
    await tester.pumpAndSettle();
    expect(find.text('러너3님을 초대할 크루'), findsOneWidget);
    await tester.tap(find.text('저녁런'));
    await tester.pumpAndSettle();
    expect(service.calls, ['invite:3:crew-2']);
    // 남은 크루(새벽런)로는 아직 초대할 수 있습니다.
    await tester.tap(menuOf('3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('크루원 초대하기'));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'invite:3:crew-1');
  });

  testWidgets('여러 크루에 속해 있으면 크루 탭에서 크루를 골라 봅니다', (tester) async {
    final service = FakeCrewService()
      ..crews = [
        FakeCrewService.crewJson(),
        {
          ...FakeCrewService.crewJson(
            owner: false,
            id: 'crew-2',
            name: '저녁런',
            icon: 'wave',
          ),
          'members': [
            {'user_id': 'me', 'nickname': '나', 'role': 'member'},
            {'user_id': '7', 'nickname': '러너7', 'role': 'owner'},
            {'user_id': '8', 'nickname': '러너8', 'role': 'member'},
          ],
        },
      ];
    final crew = CrewController(service);
    addTearDown(crew.dispose);
    await crew.refresh();
    await showSocial(tester, FakeFriendService(), crew);
    await tester.tap(find.text('크루'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crew-chip-crew-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-chip-crew-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-member-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-member-8')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('crew-chip-crew-2')));
    await tester.pumpAndSettle();
    expect(find.text('크루원 3/30명'), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-member-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-member-2')), findsNothing);
    // 크루장이 아닌 크루에서는 초대 안내를 보여주지 않습니다.
    expect(find.textContaining('크루원 초대하기'), findsNothing);
  });

  testWidgets('크루원이나 크루가 없는 사람에게는 초대 메뉴가 없습니다', (tester) async {
    final friends = FakeFriendService()
      ..entries = [friendEntry('3', FriendRelation.friend)];
    final member = CrewController(
      FakeCrewService()..crews = [FakeCrewService.crewJson(owner: false)],
    );
    addTearDown(member.dispose);
    await member.refresh();
    await showSocial(tester, friends, member);
    await tester.tap(menuOf('3'));
    await tester.pumpAndSettle();
    expect(find.text('크루원 초대하기'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    final none = CrewController(FakeCrewService());
    addTearDown(none.dispose);
    await none.refresh();
    await showSocial(tester, friends, none);
    await tester.tap(find.text('크루'));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 크루가 없어요'), findsOneWidget);
  });

  testWidgets('이미 크루가 있어도 크루 탭에서 받은 초대를 수락해 크루원이 됩니다', (tester) async {
    final service = FakeCrewService()
      ..crews = [FakeCrewService.crewJson(id: 'crew-9', name: '내 크루')]
      ..invites = [
        {
          'crew_id': 'crew-1',
          'name': '새벽런',
          'description': '',
          'icon': 'flame',
          'inviter': '러너2',
        },
      ];
    final crew = CrewController(service);
    addTearDown(crew.dispose);
    await crew.refresh();
    await showSocial(tester, FakeFriendService(), crew);
    // 받은 초대 수가 크루 탭에 표시됩니다.
    expect(
      find.descendant(of: find.byType(TabBar), matching: find.text('1')),
      findsOneWidget,
    );
    await tester.tap(find.text('크루'));
    await tester.pumpAndSettle();
    expect(find.text('러너2님의 초대'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '수락'));
    await tester.pumpAndSettle();
    expect(service.calls, ['respond:crew-1:true']);
    expect(find.text('러너2님의 초대'), findsNothing);
    // 이제 두 크루에 속하므로 크루를 골라 볼 수 있습니다.
    expect(find.byKey(const ValueKey('crew-chip-crew-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('crew-chip-crew-9')), findsOneWidget);
  });
}
