import 'dart:ui';

import 'share_layout.dart';

enum ShareSticker {
  distance('거리', [
    ShareField.distanceLabel,
    ShareField.distance,
    ShareField.unit,
  ]),
  duration('시간', [ShareField.durationLabel, ShareField.duration]),
  pace('평균 페이스', [ShareField.paceLabel, ShareField.pace]),
  temperature('기온', [ShareField.temperatureLabel, ShareField.temperature]),
  route('이동 경로', []),
  heart('평균 심박', [ShareField.heartLabel, ShareField.heart]),
  cadence('평균 케이던스', [ShareField.cadenceLabel, ShareField.cadence]);

  const ShareSticker(this.label, this.fields);
  final String label;
  final List<ShareField> fields;
}

typedef StickerPlacement = ({Offset center, double scale});

class ShareEdits {
  ShareEdits({
    required Iterable<ShareSticker> visible,
    Map<ShareSticker, StickerPlacement> placements = const {},
    this.useTemplatePlacement = false,
    this.heartRate,
    this.cadence,
  }) : visible = Set.unmodifiable(visible),
       placements = Map.unmodifiable(placements);

  final Set<ShareSticker> visible;
  final Map<ShareSticker, StickerPlacement> placements;
  final bool useTemplatePlacement;
  final int? heartRate;
  final int? cadence;

  static const templateMetrics = [
    ShareSticker.distance,
    ShareSticker.duration,
    ShareSticker.pace,
    ShareSticker.temperature,
  ];

  /// 템플릿의 지표 이름, 숫자, 단위를 한 묶음으로 서식과 함께 옮깁니다.
  ShareComposition compose(ShareLayout layout, double height) {
    final template = _template(layout, height);
    final texts = <ShareTextSlot>[];
    Rect? route;
    for (final sticker in visible) {
      final slots = _slots(sticker, template, height);
      final bounds = _bounds(sticker, height, slots, template.route);
      final adjusted = boundsFor(sticker, bounds, height);
      final scale = adjusted.width / bounds.width;
      if (sticker == ShareSticker.route) route = adjusted;
      if (useTemplatePlacement &&
          !placements.containsKey(sticker) &&
          templateMetrics.contains(sticker)) {
        texts.addAll(
          template.texts.where((slot) => sticker.fields.contains(slot.field)),
        );
        continue;
      }
      for (final slot in slots) {
        texts.add(
          ShareTextSlot(
            slot.field,
            Rect.fromLTWH(
              adjusted.left + (slot.rect.left - bounds.left) * scale,
              adjusted.top + (slot.rect.top - bounds.top) * scale,
              slot.rect.width * scale,
              slot.rect.height * scale,
            ),
            slot.size * scale,
            centered: slot.centered,
            bold: slot.bold,
          ),
        );
      }
    }
    final hasTemplateStats = templateMetrics.any(visible.contains);
    return ShareComposition(
      texts,
      route: route,
      panel: hasTemplateStats ? template.panel : null,
    );
  }

  Rect originalBounds(ShareSticker sticker, ShareLayout layout, double height) {
    final template = _template(layout, height);
    return _bounds(
      sticker,
      height,
      _slots(sticker, template, height),
      template.route,
    );
  }

  ShareComposition _template(ShareLayout layout, double height) =>
      layout.compose(
        height,
        hasRoute: useTemplatePlacement && visible.contains(ShareSticker.route),
      );

  Rect boundsFor(ShareSticker sticker, Rect bounds, double height) {
    final placement = placements[sticker];
    if (placement == null) return bounds;
    final maxScale = (1080 / bounds.width).clamp(0.0, height / bounds.height);
    final scale = placement.scale.clamp(.25, maxScale);
    final halfWidth = (bounds.width * scale / 2).clamp(0.0, 540.0);
    final halfHeight = (bounds.height * scale / 2).clamp(0.0, height / 2);
    return Rect.fromCenter(
      center: Offset(
        (placement.center.dx * 1080).clamp(halfWidth, 1080 - halfWidth),
        (placement.center.dy * height).clamp(halfHeight, height - halfHeight),
      ),
      width: halfWidth * 2,
      height: halfHeight * 2,
    );
  }

  List<ShareTextSlot> _slots(
    ShareSticker sticker,
    ShareComposition template,
    double height,
  ) {
    if (sticker == ShareSticker.heart || sticker == ShareSticker.cadence) {
      return [
        ShareTextSlot(
          sticker.fields.first,
          Rect.fromLTWH(60, height * .25, 460, 45),
          36,
          centered: true,
        ),
        ShareTextSlot(
          sticker.fields.last,
          Rect.fromLTWH(60, height * .25 + 50, 460, 90),
          70,
          centered: true,
          bold: true,
        ),
      ];
    }
    return [
      for (final slot in template.texts)
        if (sticker.fields.contains(slot.field))
          if (slot.centered && slot.rect.width > 520)
            // 실제 정보에 필요한 폭만 차지해 기본 크기에서도 좌우 이동할 수 있습니다.
            ShareTextSlot(
              slot.field,
              Rect.fromCenter(
                center: slot.rect.center,
                width: 520,
                height: slot.rect.height,
              ),
              slot.size,
              centered: true,
              bold: slot.bold,
            )
          else
            slot,
    ];
  }

  Rect _bounds(
    ShareSticker sticker,
    double height,
    List<ShareTextSlot> slots,
    Rect? templateRoute,
  ) {
    if (sticker == ShareSticker.route) {
      if (templateRoute != null) return templateRoute;
      final side = (height * .26).clamp(320.0, 500.0);
      return Rect.fromCenter(
        center: Offset(540, height * .2),
        width: side,
        height: side,
      );
    }
    return slots
        .map((slot) => slot.rect)
        .reduce((a, b) => a.expandToInclude(b));
  }
}
