import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../monetization/coin_frames.dart';
import '../progress/models/run_progress.dart';
import 'character_outfit.dart';
import 'runner_character.dart';
import 'runner_character_card.dart';

/// 프로필 카드에 담을 내용입니다: 닉네임, 레벨, 입고 있는 옷차림과 이름표.
@immutable
class CharacterCardData {
  const CharacterCardData({
    required this.nickname,
    required this.level,
    required this.outfit,
    this.items = const [],
  });

  /// 지갑에서 입고 있는 캐릭터 아이템을 읽어 만듭니다.
  factory CharacterCardData.fromWallet(
    Wallet? wallet, {
    required String nickname,
    required int level,
  }) {
    final worn = wornCharacterItems(wallet).values.toList()
      ..sort((a, b) => a.slot.index.compareTo(b.slot.index));
    return CharacterCardData(
      nickname: nickname,
      level: level,
      outfit: characterOutfit(worn),
      items: [for (final item in worn) item.label],
    );
  }

  final String nickname;
  final int level;
  final CharacterOutfit outfit;

  /// 입고 있는 아이템 이름입니다(카드에는 앞의 몇 개만 보입니다).
  final List<String> items;

  String get levelLabel => 'Lv.$level ${levelTitle(level)}';
}

/// 공유할 프로필 카드입니다. 글씨 크기 설정과 관계없이 늘 같은 모양(320×400)으로 그립니다.
class CharacterProfileCard extends StatelessWidget {
  const CharacterProfileCard({required this.data, super.key});

  static const width = 320.0;
  static const height = 400.0;

  final CharacterCardData data;

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: TrackBackgroundPainter()),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Text(
                      '뜀터 러너 카드',
                      style: TextStyle(
                        color: Color(0xFF3182F6),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 38,
              left: 0,
              right: 0,
              height: 226,
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: RunnerCharacterPainter(
                    yaw: -0.3,
                    outfit: data.outfit,
                    cheer: 0.0,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _InfoPanel(data: data),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.data});

  final CharacterCardData data;

  @override
  Widget build(BuildContext context) {
    final shown = data.items.take(3).toList();
    final more = data.items.length - shown.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10)],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              data.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF191F28),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              data.levelLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF3182F6),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.none,
              ),
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 8),
              // 이름표는 한 줄에 맞춰 보여 주고, 넘치면 살짝 줄여서 다 담습니다.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final label in shown) ...[
                      _Chip(label),
                      const SizedBox(width: 6),
                    ],
                    if (more > 0) _Chip('+$more'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFE8F3FF),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      child: Text(
        label,
        maxLines: 1,
        style: const TextStyle(
          color: Color(0xFF1B64DA),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        ),
      ),
    ),
  );
}

/// [boundaryKey]를 건 [RepaintBoundary]가 그리고 있는 카드를 PNG로 만듭니다.
Future<Uint8List> renderCharacterCardPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 2.5,
}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('카드가 아직 그려지지 않았어요.');
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('카드 이미지를 만들지 못했어요.');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}
