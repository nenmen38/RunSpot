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
        headband = item == CosmeticItem.charHeadbandRed;
        visor = item == CosmeticItem.charVisorWhite;
      case CosmeticSlot.charEyes:
        glasses = color;
      case CosmeticSlot.charTop:
        top = color;
        singlet = item == CosmeticItem.charSingletOrange;
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
    // 신발은 아래, 모자·선글라스는 위가 잘 보이게 위치를 맞춥니다.
    final focusFeet = item.slot == CosmeticSlot.charShoes;
    final focusHead =
        item.slot == CosmeticSlot.charHead ||
        item.slot == CosmeticSlot.charEyes;
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
          maxWidth:
              size *
              (focusHead
                  ? 2.2
                  : focusFeet
                  ? 2.0
                  : 1.3),
          maxHeight:
              size *
              (focusHead
                  ? 2.2
                  : focusFeet
                  ? 2.0
                  : 1.3),
          alignment: focusHead
              ? const Alignment(0, -1.05)
              : focusFeet
              ? const Alignment(0, 1.25)
              : const Alignment(0, -0.1),
          child: CustomPaint(
            size: Size.square(
              size *
                  (focusHead
                      ? 2.2
                      : focusFeet
                      ? 2.0
                      : 1.3),
            ),
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
