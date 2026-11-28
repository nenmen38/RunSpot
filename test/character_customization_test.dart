import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/character_outfit.dart';
import 'package:runquest/features/character/runner_character.dart';
import 'package:runquest/features/character/runner_character_card.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetics.dart';

import 'support/wallet_fakes.dart';

RunnerCharacterPainter _painter(WidgetTester tester, {int index = 0}) =>
    tester
            .widgetList<CustomPaint>(
              find.byKey(const ValueKey('runner-character')),
            )
            .elementAt(index)
            .painter!
        as RunnerCharacterPainter;

void main() {
  test('남자 헤어스타일 3종은 각자의 머리 모양으로 입혀집니다', () {
    expect(
      characterOutfit([CosmeticItem.charHairShort]).hairStyle,
      HairStyle.short,
    );
    expect(
      characterOutfit([CosmeticItem.charHairDandy]).hairStyle,
      HairStyle.dandy,
    );
    expect(
      characterOutfit([CosmeticItem.charHairSpiky]).hairStyle,
      HairStyle.spiky,
    );
    expect(CosmeticItem.charHairSpiky.defaultPrice, 250);
    // 머리색을 함께 입으면 남자 머리에도 그 색이 입혀집니다.
    final outfit = characterOutfit([
      CosmeticItem.charHairBlonde,
      CosmeticItem.charHairDandy,
    ]);
    expect(outfit.hairStyle, HairStyle.dandy);
    expect(outfit.hairColor, CosmeticItem.charHairBlonde.colors.first);
  });

  testWidgets('모든 헤어스타일은 여러 방향에서 오류 없이 그려집니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: [
            for (final style in HairStyle.values)
              for (final yaw in const [0.0, -1.6, 3.1])
                SizedBox(
                  width: 80,
                  height: 100,
                  child: CustomPaint(
                    painter: RunnerCharacterPainter(
                      yaw: yaw,
                      outfit: CharacterOutfit(hairStyle: style),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('새 아이템은 칸과 가격이 정해져 있고 상점에서 살 수 있습니다', () {
    final fresh = CosmeticItem.values.where(
      (item) => const {
        CosmeticSlot.charHair,
        CosmeticSlot.charHairColor,
        CosmeticSlot.charFace,
        CosmeticSlot.charPet,
        CosmeticSlot.charSeason,
      }.contains(item.slot),
    );
    // 처음 21종 + 남자 헤어스타일 3종.
    expect(fresh.length, 24);
    expect(fresh.every((item) => item.defaultPrice >= 100), isTrue);
    expect(CosmeticItem.charPetBunny.defaultPrice, 450);
    expect(CosmeticItem.charHairCurly.defaultPrice, 250);
    // 새 칸도 캐릭터 칸이라 꾸미기 창의 탭이 됩니다.
    expect(characterSlots, contains(CosmeticSlot.charPet));
    expect(characterSlots.first, CosmeticSlot.charHair);
  });

  test('착용한 아이템이 캐릭터 옷차림에 들어갑니다', () {
    final outfit = characterOutfit([
      CosmeticItem.charHairPigtails,
      CosmeticItem.charHairPink,
      CosmeticItem.charFaceHeart,
      CosmeticItem.charPetDog,
      CosmeticItem.charSeasonScarf,
      CosmeticItem.charSeasonPadding,
    ]);
    expect(outfit.hairStyle, HairStyle.pigtails);
    expect(outfit.hairColor, const Color(0xFFF58CB3));
    expect(outfit.face, CharacterFace.heart);
    expect(outfit.pet, CharacterPet.dog);
    expect(outfit.petColor, const Color(0xFFC98B4E));
    expect(outfit.petAccent, const Color(0xFF7A4A24));
    // 같은 칸의 계절 의상은 하나만 입으므로 나중 것이 이깁니다.
    expect(outfit.scarf, isNotNull);
    expect(outfit.vest, isNotNull);
    expect(characterOutfit(const []).face, CharacterFace.normal);
    expect(characterOutfit(const []).hairStyle, isNull);
  });

  test('우비는 입은 상의와 팔토시를 노란색으로 덮습니다', () {
    final outfit = characterOutfit([
      CosmeticItem.charSeasonRaincoat,
      CosmeticItem.charTeeMint,
      CosmeticItem.charSleevesBlack,
    ]);
    expect(outfit.top, const Color(0xFFFACC15));
    expect(outfit.sleeves, const Color(0xFFFACC15));
    expect(outfit.singlet, isFalse);
  });

  test('옷차림이 달라지면 같지 않고 다시 그립니다', () {
    expect(
      const CharacterOutfit(hairStyle: HairStyle.bob),
      isNot(const CharacterOutfit(hairStyle: HairStyle.bun)),
    );
    expect(
      const CharacterOutfit(pet: CharacterPet.cat),
      isNot(const CharacterOutfit()),
    );
    expect(
      const CharacterOutfit(face: CharacterFace.wink),
      const CharacterOutfit(face: CharacterFace.wink),
    );
    final a = RunnerCharacterPainter(yaw: 0);
    final b = RunnerCharacterPainter(
      yaw: 0,
      outfit: const CharacterOutfit(face: CharacterFace.star),
    );
    expect(b.shouldRepaint(a), isTrue);
  });

  testWidgets('꾸미기 창에서 헤어·표정·반려동물을 골라 입히면 캐릭터가 바뀝니다', (tester) async {
    final service = FakeWalletService()
      ..coins = 100
      ..cosmetics.addAll({
        CosmeticItem.charHairBob,
        CosmeticItem.charHairBlonde,
        CosmeticItem.charFaceWink,
        CosmeticItem.charPetCat,
      });
    final wallet = WalletController(service);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              CharacterDressButton(wallet: wallet),
              RunnerCharacterCard(wallet: wallet),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(CharacterDressButton));
    await tester.pumpAndSettle();

    // 첫 탭은 헤어스타일입니다.
    await tester.tap(find.byKey(const ValueKey('dress-char_hair_bob')));
    await tester.pumpAndSettle();
    expect(_painter(tester, index: 1).outfit.hairStyle, HairStyle.bob);

    await tester.ensureVisible(
      find.byKey(const ValueKey('dress-tab-char_haircolor')),
    );
    await tester.tap(find.byKey(const ValueKey('dress-tab-char_haircolor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dress-char_haircolor_blonde')));
    await tester.pumpAndSettle();
    expect(
      _painter(tester, index: 1).outfit.hairColor,
      const Color(0xFFE9B949),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('dress-tab-char_face')),
    );
    await tester.tap(find.byKey(const ValueKey('dress-tab-char_face')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dress-char_face_wink')));
    await tester.pumpAndSettle();
    expect(_painter(tester, index: 1).outfit.face, CharacterFace.wink);

    await tester.ensureVisible(
      find.byKey(const ValueKey('dress-tab-char_pet')),
    );
    await tester.tap(find.byKey(const ValueKey('dress-tab-char_pet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dress-char_pet_cat')));
    await tester.pumpAndSettle();
    expect(_painter(tester, index: 1).outfit.pet, CharacterPet.cat);

    // '없음'으로 반려동물을 보냅니다.
    await tester.tap(find.byKey(const ValueKey('dress-none-char_pet')));
    await tester.pumpAndSettle();
    expect(_painter(tester, index: 1).outfit.pet, isNull);
    // 프로필의 캐릭터에도 같은 모습이 이어집니다.
    expect(_painter(tester).outfit.hairStyle, HairStyle.bob);
    expect(_painter(tester).outfit.face, CharacterFace.wink);
  });
}
