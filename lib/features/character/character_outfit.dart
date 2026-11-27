import 'package:flutter/material.dart';

import '../monetization/cosmetics.dart';
import 'runner_character.dart';

/// 착용한 캐릭터 꾸미기 아이템으로 캐릭터 옷차림을 만듭니다.
CharacterOutfit characterOutfit(Iterable<CosmeticItem?> worn) {
  Color? hat, glasses, top, bottom, sleeves, shoes, shoeAccent;
  var headband = false, visor = false, singlet = false;
  for (final item in worn) {
    if (item == null || !item.slot.isCharacter) continue;
    final color = item.colors.first;
    switch (item.slot) {
      case CosmeticSlot.charHead:
        hat = color;
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
    headband: headband,
    visor: visor,
    glasses: glasses,
    top: top,
    singlet: singlet,
    bottom: bottom,
    sleeves: sleeves,
    shoes: shoes,
    shoeAccent: shoeAccent,
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
    final (zoom, focus) = switch (item.slot) {
      CosmeticSlot.charShoes => (2.0, 1.6),
      CosmeticSlot.charHead || CosmeticSlot.charEyes => (1.7, -0.73),
      _ => (1.6, 0.92),
    };
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
          alignment: Alignment(0, focus),
          child: CustomPaint(
            size: Size.square(size * zoom),
            painter: RunnerCharacterPainter(
              yaw: -0.45,
              outfit: characterOutfit([item]),
              ground: false,
            ),
          ),
        ),
      ),
    );
  }
}
