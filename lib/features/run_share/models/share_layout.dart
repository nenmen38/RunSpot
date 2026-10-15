import 'dart:ui';

enum ShareField {
  distanceLabel,
  distance,
  unit,
  durationLabel,
  duration,
  paceLabel,
  pace,
  temperatureLabel,
  temperature,
}

class ShareTextSlot {
  const ShareTextSlot(
    this.field,
    this.rect,
    this.size, {
    this.centered = false,
    this.bold = false,
  });
  final ShareField field;
  final Rect rect;
  final double size;
  final bool centered;
  final bool bold;
  bool get isLabel => const [
    ShareField.distanceLabel,
    ShareField.unit,
    ShareField.durationLabel,
    ShareField.paceLabel,
    ShareField.temperatureLabel,
  ].contains(field);
}

class ShareComposition {
  const ShareComposition(this.texts, {this.route, this.panel});
  final List<ShareTextSlot> texts;
  final Rect? route;
  final Rect? panel;
}

enum ShareLayout {
  centered('포스터', '큰 거리와 경로 중심'),
  headline('헤드라인', '상단 거리와 하단 기록'),
  board('기록 보드', '네 가지 기록을 격자로'),
  split('좌우 분할', '경로 옆에 세로 기록'),
  footer('하단 카드', '사진 위에 기록 카드');

  const ShareLayout(this.label, this.description);
  final String label;
  final String description;

  ShareComposition compose(double height, {required bool hasRoute}) {
    final texts = <ShareTextSlot>[];
    void add(
      ShareField field,
      double x,
      double y,
      double width,
      double size, {
      bool centered = false,
      bool bold = false,
    }) {
      texts.add(
        ShareTextSlot(
          field,
          Rect.fromLTWH(x, y, width, size * 1.25),
          size,
          centered: centered,
          bold: bold,
        ),
      );
    }

    void stats(double y) {
      const labels = [
        ShareField.durationLabel,
        ShareField.paceLabel,
        ShareField.temperatureLabel,
      ];
      const values = [
        ShareField.duration,
        ShareField.pace,
        ShareField.temperature,
      ];
      for (var i = 0; i < 3; i++) {
        final x = 48.0 + i * 336;
        add(values[i], x, y, 312, 66, centered: true, bold: true);
        add(labels[i], x, y + 90, 312, 36, centered: true);
      }
    }

    switch (this) {
      case ShareLayout.centered:
        final top = (height - (hasRoute ? 1330 : 510)) / 2;
        final y = top + (hasRoute ? 820 : 0);
        add(ShareField.distanceLabel, 48, y, 984, 38, centered: true);
        add(
          ShareField.distance,
          48,
          y + 45,
          984,
          220,
          centered: true,
          bold: true,
        );
        add(ShareField.unit, 48, y + 290, 984, 40, centered: true);
        stats(y + 375);
        return ShareComposition(
          texts,
          route: hasRoute ? Rect.fromLTWH(170, top, 740, 740) : null,
        );
      case ShareLayout.headline:
        add(ShareField.distanceLabel, 64, 320, 952, 38);
        add(ShareField.distance, 48, 365, 800, 270, bold: true);
        add(ShareField.unit, 860, 585, 150, 52);
        stats(height - 300);
        return ShareComposition(
          texts,
          route: hasRoute
              ? Rect.fromLTWH(
                  180,
                  770,
                  720,
                  (height - 1150).clamp(300, 720).toDouble(),
                )
              : null,
        );
      case ShareLayout.board:
        final y = hasRoute ? height - 670 : (height - 520) / 2;
        const fields = [
          ShareField.distance,
          ShareField.duration,
          ShareField.pace,
          ShareField.temperature,
        ];
        const labels = [
          ShareField.distanceLabel,
          ShareField.durationLabel,
          ShareField.paceLabel,
          ShareField.temperatureLabel,
        ];
        for (var i = 0; i < 4; i++) {
          final x = 64.0 + (i % 2) * 520;
          final top = y + (i ~/ 2) * 280;
          add(labels[i], x, top, 432, 36);
          add(fields[i], x, top + 55, 432, i == 0 ? 132 : 100, bold: true);
        }
        add(ShareField.unit, 64, y + 225, 432, 30);
        final side = (height - 970).clamp(320, 740).toDouble();
        return ShareComposition(
          texts,
          route: hasRoute
              ? Rect.fromLTWH((1080 - side) / 2, 180, side, side)
              : null,
        );
      case ShareLayout.split:
        final y = (height - 870) / 2;
        final x = hasRoute ? 590.0 : 200.0;
        final w = hasRoute ? 426.0 : 680.0;
        add(ShareField.distanceLabel, x, y, w, 36);
        add(ShareField.distance, x, y + 55, w, 175, bold: true);
        add(ShareField.unit, x, y + 260, w, 38);
        const labels = [
          ShareField.durationLabel,
          ShareField.paceLabel,
          ShareField.temperatureLabel,
        ];
        const values = [
          ShareField.duration,
          ShareField.pace,
          ShareField.temperature,
        ];
        for (var i = 0; i < 3; i++) {
          add(labels[i], x, y + 370 + i * 170, w, 32);
          add(values[i], x, y + 415 + i * 170, w, 76, bold: true);
        }
        return ShareComposition(
          texts,
          route: hasRoute
              ? Rect.fromLTWH(64, (height - 460) / 2, 460, 460)
              : null,
        );
      case ShareLayout.footer:
        final y = height - 610;
        add(ShareField.distanceLabel, 92, y + 55, 410, 36);
        add(ShareField.distance, 80, y + 125, 430, 160, bold: true);
        add(ShareField.unit, 92, y + 335, 410, 40);
        const labels = [
          ShareField.durationLabel,
          ShareField.paceLabel,
          ShareField.temperatureLabel,
        ];
        const values = [
          ShareField.duration,
          ShareField.pace,
          ShareField.temperature,
        ];
        for (var i = 0; i < 3; i++) {
          add(labels[i], 590, y + 45 + i * 140, 400, 30);
          add(values[i], 590, y + 90 + i * 140, 400, 64, bold: true);
        }
        final side = (height - 950).clamp(300, 780).toDouble();
        return ShareComposition(
          texts,
          route: hasRoute
              ? Rect.fromLTWH(
                  (1080 - side) / 2,
                  (height - 750 - side) / 2,
                  side,
                  side,
                )
              : null,
          panel: Rect.fromLTWH(48, y, 984, 500),
        );
    }
  }
}
