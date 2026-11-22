import 'package:flutter/material.dart';

/// 꾸미기 아이템을 착용하는 칸입니다. 칸마다 하나만 착용합니다.
enum CosmeticSlot {
  route('route', '경로 색', '러닝 중 지도에 그려지는 내 경로 선 색'),
  titleStyle('title_style', '칭호 모양', '닉네임 옆 칭호 배지의 색과 아이콘'),
  chatBubble('chat_bubble', '말풍선', '친구와의 대화에서 내 말풍선 색');

  const CosmeticSlot(this.code, this.label, this.description);
  final String code;
  final String label;
  final String description;

  static CosmeticSlot? fromCode(Object? code) =>
      values.where((slot) => slot.code == code).firstOrNull;
}

/// 코인으로 사는 꾸미기 아이템입니다. 가격은 서버(cosmetic_price)와 같아야 합니다.
enum CosmeticItem {
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
  ]);

  const CosmeticItem(
    this.code,
    this.slot,
    this.label,
    this.defaultPrice,
    this.colors,
  );
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
