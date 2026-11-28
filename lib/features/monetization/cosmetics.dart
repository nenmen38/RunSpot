import 'package:flutter/material.dart';

/// 꾸미기 아이템을 착용하는 칸입니다. 칸마다 하나만 착용합니다.
enum CosmeticSlot {
  route('route', '경로 색', '러닝 중 지도에 그려지는 내 경로 선 색'),
  titleStyle('title_style', '칭호 모양', '닉네임 옆 칭호 배지의 색과 아이콘'),
  chatBubble('chat_bubble', '말풍선', '친구와의 대화에서 내 말풍선 색'),
  shareCard('share_card', '공유 카드', '러닝 기록을 공유할 때 고르는 카드'),

  // 내 러너 캐릭터가 입는 칸입니다. 프로필의 캐릭터 '꾸미기'에서 착용합니다.
  charHair('char_hair', '헤어스타일', '캐릭터의 머리 모양'),
  charHairColor('char_haircolor', '머리색', '헤어스타일에 입히는 머리색'),
  charFace('char_face', '표정', '캐릭터의 눈 표정'),
  charHead('char_head', '모자', '캐릭터 머리에 쓰는 캡·썬캡·머리띠'),
  charEyes('char_eyes', '선글라스', '캐릭터 얼굴에 쓰는 스포츠 선글라스'),
  charTop('char_top', '상의', '캐릭터가 입는 러닝 싱글렛·티셔츠'),
  charBottom('char_bottom', '하의', '캐릭터가 입는 러닝 쇼츠'),
  charSleeves('char_sleeves', '팔토시', '캐릭터 팔에 끼는 팔토시'),
  charShoes('char_shoes', '운동화', '캐릭터가 신는 러닝화'),
  charSeason('char_season', '계절 의상', '목도리·패딩 조끼·우비 같은 계절 옷'),
  charPet('char_pet', '반려동물', '캐릭터 곁에 서는 귀여운 친구');

  const CosmeticSlot(this.code, this.label, this.description);
  final String code;
  final String label;
  final String description;

  static CosmeticSlot? fromCode(Object? code) =>
      values.where((slot) => slot.code == code).firstOrNull;

  /// 내 러너 캐릭터가 입는 칸인지입니다.
  bool get isCharacter => code.startsWith('char_');
}

/// 코인으로 사는 꾸미기 아이템입니다. 가격은 서버(cosmetic_price)와 같아야 합니다.
enum CosmeticItem {
  shareMinimal('share_minimal', CosmeticSlot.shareCard, '미니멀 카드', 100, [
    Color(0xFFE3EBE7),
  ]),
  shareNight('share_night', CosmeticSlot.shareCard, '야간 러닝 카드', 200, [
    Color(0xFF0F1830),
    Color(0xFF675DE0),
  ]),
  routeNeon('route_neon', CosmeticSlot.route, '네온 핑크', 400, [
    Color(0xFFFF2D95),
  ]),
  routeGold('route_gold', CosmeticSlot.route, '골드', 600, [Color(0xFFD4A017)]),
  routeRainbow('route_rainbow', CosmeticSlot.route, '무지개', 800, [
    Color(0xFFEF4444),
    Color(0xFFF97316),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
  ]),
  titleGold('title_gold', CosmeticSlot.titleStyle, '골드 배지', 300, [
    Color(0xFFD4A017),
  ]),
  titleNeon('title_neon', CosmeticSlot.titleStyle, '네온 배지', 400, [
    Color(0xFF22D3EE),
  ]),
  titleGradient('title_gradient', CosmeticSlot.titleStyle, '그라데이션 배지', 500, [
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ]),
  titleCrown('title_crown', CosmeticSlot.titleStyle, '왕관 아이콘', 300, [
    Color(0xFFEAB308),
  ]),
  titleFire('title_fire', CosmeticSlot.titleStyle, '불꽃 아이콘', 300, [
    Color(0xFFF97316),
  ]),
  bubbleMint('bubble_mint', CosmeticSlot.chatBubble, '민트', 200, [
    Color(0xFF14B8A6),
  ]),
  bubbleSunset('bubble_sunset', CosmeticSlot.chatBubble, '선셋', 200, [
    Color(0xFFF97316),
    Color(0xFFEC4899),
  ]),
  bubbleNight('bubble_night', CosmeticSlot.chatBubble, '나이트', 200, [
    Color(0xFF1E293B),
  ]),
  bubblePink('bubble_pink', CosmeticSlot.chatBubble, '핑크', 200, [
    Color(0xFFEC4899),
  ]),

  // 내 러너 캐릭터 꾸미기입니다. 가격은 서버(cosmetic_price)와 같습니다.
  charCapBlue('char_cap_blue', CosmeticSlot.charHead, '블루 러닝캡', 150, [
    Color(0xFF1B64DA),
  ]),
  charCapBlack('char_cap_black', CosmeticSlot.charHead, '블랙 러닝캡', 150, [
    Color(0xFF1F2937),
  ]),
  charVisorWhite('char_visor_white', CosmeticSlot.charHead, '화이트 썬캡', 200, [
    Color(0xFFCBD5E1),
  ]),
  charHeadbandRed('char_headband_red', CosmeticSlot.charHead, '레드 헤어밴드', 100, [
    Color(0xFFEF4444),
  ]),
  charGlassesBlack(
    'char_glasses_black',
    CosmeticSlot.charEyes,
    '블랙 스포츠 선글라스',
    200,
    [Color(0xFF1F2937)],
  ),
  charGlassesMirror(
    'char_glasses_mirror',
    CosmeticSlot.charEyes,
    '블루 미러 선글라스',
    250,
    [Color(0xFF2563EB), Color(0xFF22D3EE)],
  ),
  charSingletOrange(
    'char_singlet_orange',
    CosmeticSlot.charTop,
    '오렌지 러닝 싱글렛',
    200,
    [Color(0xFFF97316)],
  ),
  charTeeMint('char_tee_mint', CosmeticSlot.charTop, '민트 러닝 티', 200, [
    Color(0xFF14B8A6),
  ]),
  charTeeNavy('char_tee_navy', CosmeticSlot.charTop, '네이비 크루 티', 250, [
    Color(0xFF1E3A8A),
  ]),
  charShortsBlack(
    'char_shorts_black',
    CosmeticSlot.charBottom,
    '블랙 러닝 쇼츠',
    150,
    [Color(0xFF111827)],
  ),
  charShortsBlue('char_shorts_blue', CosmeticSlot.charBottom, '블루 러닝 쇼츠', 150, [
    Color(0xFF2563EB),
  ]),
  charSleevesBlack(
    'char_sleeves_black',
    CosmeticSlot.charSleeves,
    '블랙 팔토시',
    150,
    [Color(0xFF111827)],
  ),
  charSleevesNeon(
    'char_sleeves_neon',
    CosmeticSlot.charSleeves,
    '네온 팔토시',
    200,
    [Color(0xFFA3E635)],
  ),
  charShoesRed('char_shoes_red', CosmeticSlot.charShoes, '레드 러닝화', 250, [
    Color(0xFFEF4444),
  ]),
  charShoesNeon('char_shoes_neon', CosmeticSlot.charShoes, '네온 러닝화', 300, [
    Color(0xFFA3E635),
    Color(0xFF111827),
  ]),
  charShoesCarbon('char_shoes_carbon', CosmeticSlot.charShoes, '카본 레이싱화', 450, [
    Color(0xFF111827),
    Color(0xFFF97316),
  ]),

  // 헤어스타일: 머리 모양입니다(머리색은 따로 고릅니다).
  charHairBob('char_hair_bob', CosmeticSlot.charHair, '단발머리', 200, [
    Color(0xFF5B3A29),
  ]),
  charHairPonytail('char_hair_ponytail', CosmeticSlot.charHair, '포니테일', 200, [
    Color(0xFF5B3A29),
  ]),
  charHairPigtails('char_hair_pigtails', CosmeticSlot.charHair, '양갈래', 200, [
    Color(0xFF5B3A29),
  ]),
  charHairBun('char_hair_bun', CosmeticSlot.charHair, '똥머리', 200, [
    Color(0xFF5B3A29),
  ]),
  charHairCurly('char_hair_curly', CosmeticSlot.charHair, '뽀글머리', 250, [
    Color(0xFF5B3A29),
  ]),
  // 남자 헤어스타일.
  charHairShort('char_hair_short', CosmeticSlot.charHair, '짧은 머리', 200, [
    Color(0xFF5B3A29),
  ]),
  charHairDandy('char_hair_dandy', CosmeticSlot.charHair, '댄디컷', 200, [
    Color(0xFF5B3A29),
  ]),
  charHairSpiky('char_hair_spiky', CosmeticSlot.charHair, '삐죽머리', 250, [
    Color(0xFF5B3A29),
  ]),

  // 머리색: 헤어스타일을 입고 있을 때 그 색으로 바뀝니다.
  charHairBlack('char_haircolor_black', CosmeticSlot.charHairColor, '흑발', 100, [
    Color(0xFF26201E),
  ]),
  charHairChestnut(
    'char_haircolor_chestnut',
    CosmeticSlot.charHairColor,
    '밤색',
    100,
    [Color(0xFF7A4A2B)],
  ),
  charHairBlonde(
    'char_haircolor_blonde',
    CosmeticSlot.charHairColor,
    '금발',
    150,
    [Color(0xFFE9B949)],
  ),
  charHairPink('char_haircolor_pink', CosmeticSlot.charHairColor, '핑크', 200, [
    Color(0xFFF58CB3),
  ]),
  charHairSky('char_haircolor_sky', CosmeticSlot.charHairColor, '하늘색', 200, [
    Color(0xFF5BA8F5),
  ]),

  // 표정: 눈 모양입니다(선글라스를 쓰면 가려집니다).
  charFaceWink('char_face_wink', CosmeticSlot.charFace, '윙크', 150, [
    Color(0xFF1F2836),
  ]),
  charFaceHeart('char_face_heart', CosmeticSlot.charFace, '하트 눈', 200, [
    Color(0xFFFF4D7A),
  ]),
  charFaceStar('char_face_star', CosmeticSlot.charFace, '반짝 눈', 200, [
    Color(0xFFFFD43B),
  ]),
  charFaceHappy('char_face_happy', CosmeticSlot.charFace, '웃는 눈', 150, [
    Color(0xFF1F2836),
  ]),

  // 계절 의상: 목도리·패딩 조끼·우비입니다.
  charSeasonScarf('char_season_scarf', CosmeticSlot.charSeason, '겨울 목도리', 250, [
    Color(0xFFE11D48),
    Color(0xFFFFFFFF),
  ]),
  charSeasonPadding(
    'char_season_padding',
    CosmeticSlot.charSeason,
    '패딩 조끼',
    300,
    [Color(0xFF1E3A8A)],
  ),
  charSeasonRaincoat(
    'char_season_raincoat',
    CosmeticSlot.charSeason,
    '노란 우비',
    250,
    [Color(0xFFFACC15)],
  ),

  // 반려동물: 캐릭터 곁에 서 있습니다.
  charPetChick('char_pet_chick', CosmeticSlot.charPet, '병아리', 300, [
    Color(0xFFFFD43B),
    Color(0xFFF59E0B),
  ]),
  charPetDog('char_pet_dog', CosmeticSlot.charPet, '강아지', 400, [
    Color(0xFFC98B4E),
    Color(0xFF7A4A24),
  ]),
  charPetCat('char_pet_cat', CosmeticSlot.charPet, '고양이', 400, [
    Color(0xFF9CA3AF),
    Color(0xFF4B5563),
  ]),
  charPetBunny('char_pet_bunny', CosmeticSlot.charPet, '토끼', 450, [
    Color(0xFFFFFFFF),
    Color(0xFFF4A6B8),
  ]),

  // 레벨 보상: 상점에서 살 수 없고, 레벨에 도달하면 자동으로 선물로 받습니다.
  charHeadbandGold('char_headband_gold', CosmeticSlot.charHead, '골드 헤어밴드', 0, [
    Color(0xFFF5B700),
  ], unlockLevel: 5),
  charShoesRainbow('char_shoes_rainbow', CosmeticSlot.charShoes, '무지개 러닝화', 0, [
    Color(0xFF8B5CF6),
    Color(0xFFFFD43B),
  ], unlockLevel: 10),
  charSingletGold('char_singlet_gold', CosmeticSlot.charTop, '챔피언 골드 싱글렛', 0, [
    Color(0xFFF5B700),
  ], unlockLevel: 20),

  // 챌린지 보상: 12월 챌린지 세 가지를 모두 마치면 선물로 받습니다.
  charCapSanta('char_cap_santa', CosmeticSlot.charHead, '산타 러닝캡', 0, [
    Color(0xFFE11D48),
    Color(0xFFFFFFFF),
  ], challengeMonth: 12);

  const CosmeticItem(
    this.code,
    this.slot,
    this.label,
    this.defaultPrice,
    this.colors, {
    this.unlockLevel,
    this.challengeMonth,
  });

  /// 레벨 보상 아이템이면 받을 수 있는 레벨입니다(상점에서 살 수 없음).
  final int? unlockLevel;
  bool get isLevelReward => unlockLevel != null;

  /// 챌린지 보상이면 그 달(1~12)입니다(상점에서 살 수 없음).
  final int? challengeMonth;

  /// 레벨·챌린지로만 받는 아이템인지입니다.
  bool get isReward => unlockLevel != null || challengeMonth != null;

  /// 상점 버튼에 쓰는 짧은 받는 방법입니다(예: 'Lv.5 선물', '12월 챌린지').
  String? get rewardButton => switch ((unlockLevel, challengeMonth)) {
    (final level?, _) => 'Lv.$level 선물',
    (_, final month?) => '$month월 챌린지',
    _ => null,
  };

  /// 상점 설명에 쓰는 받는 방법입니다.
  String? get rewardNote => switch ((unlockLevel, challengeMonth)) {
    (final level?, _) => '레벨 $level 달성 보상 · 무료',
    (_, final month?) => '$month월 챌린지 완주 보상 · 무료',
    _ => null,
  };
  final String code;
  final CosmeticSlot slot;
  final String label;
  final int defaultPrice;

  /// 아이템의 대표 색입니다. 여러 개면 그라데이션이나 무지개로 씁니다.
  final List<Color> colors;

  static CosmeticItem? fromCode(Object? code) =>
      values.where((item) => item.code == code).firstOrNull;

  /// 칭호 배지에 붙는 아이콘입니다(칭호 모양 칸만).
  IconData? get titleIcon => switch (this) {
    titleCrown => Icons.workspace_premium,
    titleFire => Icons.local_fire_department,
    _ => null,
  };
}

/// 달려서 얻는 칭호입니다. 조건은 서버(title_progress)가 계산합니다.
enum RunnerTitle {
  tenK('ten_k', '10K 클럽', '한 번에 10km 완주', Icons.flag),
  half('half', '하프 마라토너', '한 번에 21.1km 완주', Icons.emoji_events),
  dawn('dawn', '새벽 러너', '오전 6시 전에 시작한 러닝 10회', Icons.wb_twilight),
  steady('steady', '꾸준왕', '주간 목표 4주 연속 달성', Icons.event_available),
  crewLeader('crew_leader', '크루 리더', '크루원 10명 이상인 크루의 크루장', Icons.groups),
  together('together', '함께 달리기', '함께 달리기 10회 완주', Icons.directions_run);

  const RunnerTitle(this.code, this.label, this.condition, this.icon);
  final String code;
  final String label;
  final String condition;
  final IconData icon;

  static RunnerTitle? fromCode(Object? code) =>
      values.where((title) => title.code == code).firstOrNull;
}

/// 닉네임 옆에 붙는 칭호 배지입니다. 칭호 모양 아이템을 착용했으면 그 모양으로 그립니다.
class TitleBadge extends StatelessWidget {
  const TitleBadge({
    required this.title,
    this.style,
    this.size = 11,
    super.key,
  });

  final RunnerTitle title;
  final CosmeticItem? style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = this.style;
    final colors = style?.colors ?? const [Color(0xFF64748B)];
    final icon = style?.titleIcon;
    final filled = style != null && style != CosmeticItem.titleNeon;
    return Semantics(
      label: '칭호 ${title.label}',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: size * .55, vertical: 1),
          decoration: BoxDecoration(
            color: filled && colors.length == 1 ? colors.first : null,
            gradient: filled && colors.length > 1
                ? LinearGradient(colors: colors)
                : null,
            borderRadius: BorderRadius.circular(size),
            border: filled ? null : Border.all(color: colors.first),
            boxShadow: style == CosmeticItem.titleNeon
                ? [
                    BoxShadow(
                      color: colors.first.withValues(alpha: .6),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: size + 1, color: Colors.white),
                const SizedBox(width: 2),
              ],
              Flexible(
                child: Text(
                  title.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: filled ? Colors.white : colors.first,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 말풍선 아이템의 배경입니다.
BoxDecoration? bubbleDecoration(CosmeticItem? item) {
  if (item == null || item.slot != CosmeticSlot.chatBubble) return null;
  return item.colors.length > 1
      ? BoxDecoration(gradient: LinearGradient(colors: item.colors))
      : BoxDecoration(color: item.colors.first);
}

/// 경로 색 아이템으로 경로를 칠합니다. 한 가지 색이면 모든 선을 그 색으로,
/// 무지개처럼 여러 색이면 경로를 몇 점씩 나눠 색을 돌려 가며 칠합니다.
/// 아이템이 없으면 색 없이(지도 기본 초록) 그대로 돌려줍니다.
({List<List<T>> segments, List<String>? colors}) skinRoute<T>(
  List<List<T>> segments,
  CosmeticItem? item, {
  int chunk = 8,
}) {
  if (item == null || item.slot != CosmeticSlot.route) {
    return (segments: segments, colors: null);
  }
  String hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  if (item.colors.length == 1) {
    final color = hex(item.colors.first);
    return (segments: segments, colors: [for (final _ in segments) color]);
  }
  final pieces = <List<T>>[];
  final colors = <String>[];
  var index = 0;
  for (final segment in segments) {
    if (segment.length < 2) {
      pieces.add(segment);
      colors.add(hex(item.colors[index++ % item.colors.length]));
      continue;
    }
    // 조각끼리 끝점을 겹쳐 선이 끊겨 보이지 않게 합니다.
    for (var start = 0; start < segment.length - 1; start += chunk) {
      final end = (start + chunk).clamp(0, segment.length - 1);
      pieces.add(segment.sublist(start, end + 1));
      colors.add(hex(item.colors[index++ % item.colors.length]));
    }
  }
  return (segments: pieces, colors: colors);
}
