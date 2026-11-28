import 'package:flutter/material.dart';

import '../monetization/cosmetics.dart';
import 'runner_character.dart';

/// 착용한 캐릭터 꾸미기 아이템으로 캐릭터 옷차림을 만듭니다.
CharacterOutfit characterOutfit(Iterable<CosmeticItem?> worn) {
  Color? hat, hatTrim, glasses, top, bottom, sleeves, shoes, shoeAccent;
  Color? hairColor, petColor, petAccent, scarf, scarfTrim, vest;
  HairStyle? hairStyle;
  CharacterPet? pet;
  var face = CharacterFace.normal;
  var headband = false, visor = false, singlet = false;
  // 계절 의상(우비)이 상의·팔토시를 덮을 수 있게 칸 순서대로 입힙니다.
  final items = [
    for (final item in worn)
      if (item != null && item.slot.isCharacter) item,
  ]..sort((a, b) => a.slot.index.compareTo(b.slot.index));
  for (final item in items) {
    final color = item.colors.first;
    switch (item.slot) {
      case CosmeticSlot.charHair:
        hairStyle = switch (item) {
          CosmeticItem.charHairBob => HairStyle.bob,
          CosmeticItem.charHairPonytail => HairStyle.ponytail,
          CosmeticItem.charHairPigtails => HairStyle.pigtails,
          CosmeticItem.charHairBun => HairStyle.bun,
          CosmeticItem.charHairShort => HairStyle.short,
          CosmeticItem.charHairDandy => HairStyle.dandy,
          CosmeticItem.charHairSpiky => HairStyle.spiky,
          _ => HairStyle.curly,
        };
      case CosmeticSlot.charHairColor:
        hairColor = color;
      case CosmeticSlot.charFace:
        face = switch (item) {
          CosmeticItem.charFaceWink => CharacterFace.wink,
          CosmeticItem.charFaceHeart => CharacterFace.heart,
          CosmeticItem.charFaceStar => CharacterFace.star,
          _ => CharacterFace.happy,
        };
      case CosmeticSlot.charPet:
        pet = switch (item) {
          CosmeticItem.charPetChick => CharacterPet.chick,
          CosmeticItem.charPetDog => CharacterPet.dog,
          CosmeticItem.charPetCat => CharacterPet.cat,
          _ => CharacterPet.bunny,
        };
        petColor = color;
        petAccent = item.colors.length > 1 ? item.colors[1] : null;
      case CosmeticSlot.charSeason:
        switch (item) {
          case CosmeticItem.charSeasonScarf:
            scarf = color;
            scarfTrim = item.colors[1];
          case CosmeticItem.charSeasonPadding:
            vest = color;
          default:
            // 우비: 상의와 팔을 노란색으로 덮습니다.
            top = color;
            singlet = false;
            sleeves = color;
        }
      case CosmeticSlot.charHead:
        hat = color;
        hatTrim = item == CosmeticItem.charCapSanta ? item.colors[1] : null;
        headband =
            item == CosmeticItem.charHeadbandRed ||
            item == CosmeticItem.charHeadbandGold;
        visor = item == CosmeticItem.charVisorWhite;
      case CosmeticSlot.charEyes:
        glasses = color;
      case CosmeticSlot.charTop:
        top = color;
        singlet =
            item == CosmeticItem.charSingletOrange ||
            item == CosmeticItem.charSingletGold;
      case CosmeticSlot.charBottom:
        bottom = color;
      case CosmeticSlot.charSleeves:
        sleeves = color;
      case CosmeticSlot.charShoes:
        shoes = color;
        shoeAccent = item.colors.length > 1 ? item.colors[1] : Colors.white;
      default:
        break;
    }
  }
  return CharacterOutfit(
    hat: hat,
    hatTrim: hatTrim,
    headband: headband,
    visor: visor,
    glasses: glasses,
    top: top,
    singlet: singlet,
    bottom: bottom,
    sleeves: sleeves,
    shoes: shoes,
    shoeAccent: shoeAccent,
    hairStyle: hairStyle,
    hairColor: hairColor,
    face: face,
    pet: pet,
    petColor: petColor,
    petAccent: petAccent,
    scarf: scarf,
    scarfTrim: scarfTrim,
    vest: vest,
  );
}

/// 상점·꾸미기 칩에 쓰는 작은 캐릭터 미리보기입니다. 그 아이템만 입은 모습을 보여줍니다.
class CharacterItemPreview extends StatelessWidget {
  const CharacterItemPreview({required this.item, this.size = 44, super.key});

  final CosmeticItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 신발은 발, 모자·선글라스는 얼굴, 옷은 몸통이 동그라미 가운데 오게 확대합니다.
    final (zoom, focus, shift) = switch (item.slot) {
      CosmeticSlot.charShoes => (2.0, 1.6, 0.0),
      CosmeticSlot.charHead ||
      CosmeticSlot.charEyes ||
      CosmeticSlot.charHair ||
      CosmeticSlot.charHairColor ||
      CosmeticSlot.charFace => (1.7, -0.73, 0.0),
      // 반려동물은 캐릭터 오른쪽 아래에 서 있어 그쪽으로 확대합니다.
      CosmeticSlot.charPet => (2.6, 1.3, 0.62),
      _ => (1.6, 0.92, 0.0),
    };
    // 머리색은 단발머리에 입혀서 보여 줍니다.
    final outfit = item.slot == CosmeticSlot.charHairColor
        ? CharacterOutfit(
            hairStyle: HairStyle.bob,
            hairColor: item.colors.first,
          )
        : characterOutfit([item]);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFE8F3FF),
          border: Border.all(color: const Color(0xFFD6E6FB), width: 2),
        ),
        child: OverflowBox(
          maxWidth: size * zoom,
          maxHeight: size * zoom,
          alignment: Alignment(shift, focus),
          child: CustomPaint(
            size: Size.square(size * zoom),
            painter: RunnerCharacterPainter(
              yaw: -0.45,
              outfit: outfit,
              ground: false,
            ),
          ),
        ),
      ),
    );
  }
}
