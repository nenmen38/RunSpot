import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/board_compose_screen.dart';
import 'package:runquest/features/board/board_controller.dart';
import 'package:runquest/features/board/board_share_intent.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:runquest/features/character/character_card_share.dart';
import 'package:runquest/features/character/character_profile_card.dart';
import 'package:runquest/features/character/runner_character.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetics.dart';

import 'share_photo_test.dart' show photoBytes;
import 'support/board_fakes.dart';
import 'support/wallet_fakes.dart';

class FakeCardActions implements CharacterCardActions {
  final saved = <Uint8List>[];
  final shared = <Uint8List>[];
  final sent = <(ChatTarget, Uint8List)>[];
  final boards = <Uint8List>[];
  Object? saveFailure;
  List<ChatTarget> targets = const [
    ChatTarget(id: 'friend-1', name: '민지', isRoom: false),
    ChatTarget(id: 'room-1', name: '새벽 러닝방', isRoom: true),
  ];

  @override
  Future<void> saveImage(Uint8List png) async {
    if (saveFailure != null) throw saveFailure!;
    saved.add(png);
  }

  @override
  Future<void> shareImage(Uint8List png, Rect origin) async => shared.add(png);

  @override
  Future<Uint8List> toJpeg(Uint8List png) async =>
      Uint8List.fromList([0xFF, 0xD8, ...png.take(8)]);

  @override
  Future<List<ChatTarget>> chatTargets() async => targets;

  @override
  Future<void> sendToChat(ChatTarget target, Uint8List jpeg) async =>
      sent.add((target, jpeg));

  @override
  void openBoard(Uint8List jpeg) => boards.add(jpeg);
}

const data = CharacterCardData(
  nickname: '뜀터러너',
  level: 12,
  outfit: CharacterOutfit.none,
  items: ['양갈래', '핑크', '하트 눈', '산타 러닝캡', '강아지'],
);

Future<void> openSheet(WidgetTester tester, FakeCardActions actions) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showCharacterCardSheet(context, data: data, actions: actions),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

/// 카드를 PNG로 그리는 데는 실제 비동기 처리가 필요해 가짜 시계 밖에서 기다립니다.
Future<void> tapAndRender(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await tester.pumpAndSettle();
}

void main() {
  test('카드 내용은 지갑에서 입은 캐릭터 아이템과 레벨 이름표를 읽습니다', () async {
    final service = FakeWalletService()
      ..cosmetics.addAll({
        CosmeticItem.charPetDog,
        CosmeticItem.charHairBob,
        CosmeticItem.routeNeon,
      })
      ..equippedCosmetics[CosmeticSlot.charPet] = CosmeticItem.charPetDog
      ..equippedCosmetics[CosmeticSlot.charHair] = CosmeticItem.charHairBob
      ..equippedCosmetics[CosmeticSlot.route] = CosmeticItem.routeNeon;
    final wallet = WalletController(service);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    final card = CharacterCardData.fromWallet(
      wallet.wallet,
      nickname: '러너',
      level: 5,
    );
    // 캐릭터 칸 아이템만, 헤어 → 반려동물 순서로 담깁니다.
    expect(card.items, ['단발머리', '강아지']);
    expect(card.outfit.pet, isNotNull);
    expect(card.levelLabel, startsWith('Lv.5 '));
  });

  testWidgets('카드는 닉네임·레벨·이름표를 보여 주고 이름표가 많으면 +N으로 줄입니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CharacterProfileCard(data: data)),
      ),
    );
    expect(find.text('뜀터러너'), findsOneWidget);
    expect(find.textContaining('Lv.12'), findsOneWidget);
    expect(find.text('양갈래'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('산타 러닝캡'), findsNothing);
  });

  testWidgets('이미지 저장은 카드를 PNG로 만들어 앨범에 저장합니다', (tester) async {
    final actions = FakeCardActions();
    await openSheet(tester, actions);
    await tapAndRender(tester, find.byKey(const ValueKey('card-save')));
    expect(actions.saved, hasLength(1));
    // PNG 파일 머리(89 50 4E 47)입니다.
    expect(actions.saved.single.take(4), [0x89, 0x50, 0x4E, 0x47]);
    // 320×400 카드를 2.5배로 그립니다.
    expect(actions.saved.single.length, greaterThan(1000));
    expect(find.text('갤러리에 저장했어요.'), findsOneWidget);
  });

  testWidgets('저장에 실패하면 이유를 알려 줍니다', (tester) async {
    final actions = FakeCardActions()..saveFailure = StateError('실패');
    await openSheet(tester, actions);
    await tapAndRender(tester, find.byKey(const ValueKey('card-save')));
    expect(actions.saved, isEmpty);
    expect(find.textContaining('처리하지 못했어요'), findsOneWidget);
  });

  testWidgets('공유하기는 기기 공유 창으로 카드 이미지를 넘깁니다', (tester) async {
    final actions = FakeCardActions();
    await openSheet(tester, actions);
    await tapAndRender(tester, find.text('공유하기'));
    expect(actions.shared, hasLength(1));
  });

  testWidgets('채팅으로 보내기는 친구·대화방 중 고른 곳에 JPEG로 보냅니다', (tester) async {
    final actions = FakeCardActions();
    await openSheet(tester, actions);
    await tester.tap(find.byKey(const ValueKey('card-chat')));
    await tester.pumpAndSettle();
    expect(find.text('누구에게 보낼까요?'), findsOneWidget);
    expect(find.text('친구'), findsOneWidget);
    expect(find.text('대화방'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('target-room-1')));
    // 고른 창이 닫힌 뒤에 카드를 그려 보내므로, 닫히는 동안은 화면을 돌리고 그 뒤에 실제 시간을 기다립니다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pumpAndSettle();
    expect(actions.sent, hasLength(1));
    expect(actions.sent.single.$1.name, '새벽 러닝방');
    expect(actions.sent.single.$1.isRoom, isTrue);
    // JPEG 머리(FF D8)로 바뀐 이미지가 갑니다.
    expect(actions.sent.single.$2.take(2), [0xFF, 0xD8]);
    expect(find.text('새벽 러닝방에게 카드를 보냈어요.'), findsOneWidget);
  });

  testWidgets('보낼 친구가 없으면 안내합니다', (tester) async {
    final actions = FakeCardActions()..targets = const [];
    await openSheet(tester, actions);
    await tester.tap(find.byKey(const ValueKey('card-chat')));
    await tester.pumpAndSettle();
    expect(find.textContaining('보낼 친구나 대화방이 아직 없어요'), findsOneWidget);
  });

  testWidgets('게시판에 올리기는 창을 닫고 JPEG를 게시판으로 넘깁니다', (tester) async {
    final actions = FakeCardActions();
    await openSheet(tester, actions);
    await tapAndRender(tester, find.byKey(const ValueKey('card-board')));
    expect(actions.boards, hasLength(1));
    expect(actions.boards.single.take(2), [0xFF, 0xD8]);
    expect(find.text('내 러너 프로필 카드'), findsNothing);
  });

  test('게시판 사진 쪽지는 한 번만 꺼낼 수 있습니다', () {
    final intent = BoardShareIntent.instance;
    intent.photo = Uint8List.fromList([1, 2, 3]);
    expect(intent.take(), [1, 2, 3]);
    expect(intent.take(), isNull);
  });

  testWidgets('게시판 글쓰기는 카드 사진이 붙은 채로 열립니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = BoardController(FakeBoardService())
      ..kind = BoardKind.national;
    addTearDown(controller.dispose);
    await controller.refresh();
    final photo = (await tester.runAsync(photoBytes))!;
    await tester.pumpWidget(
      MaterialApp(
        home: BoardComposeScreen(
          controller: controller,
          initialPhotos: [photo],
        ),
      ),
    );
    // 사진을 실제로 읽어 미리보기를 그릴 수 있게 실제 시간을 잠깐 기다립니다.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photos')), findsOneWidget);
    expect(find.textContaining('사진 1/'), findsOneWidget);
  });
}
