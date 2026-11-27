import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

part 'runner_character_extras.dart';

/// 머리 모양입니다(단발·포니테일·양갈래·똥머리·뽀글머리).
enum HairStyle { bob, ponytail, pigtails, bun, curly }

/// 표정입니다. 선글라스를 쓰면 눈은 가려집니다.
enum CharacterFace { normal, wink, heart, star, happy }

/// 곁에 서 있는 반려동물입니다.
enum CharacterPet { chick, dog, cat, bunny }

/// 캐릭터가 입은 꾸미기입니다. 칸마다 색(없으면 맨몸)을 줍니다.
@immutable
class CharacterOutfit {
  const CharacterOutfit({
    this.hat,
    this.headband = false,
    this.glasses,
    this.top,
    this.singlet = false,
    this.bottom,
    this.sleeves,
    this.shoes,
    this.shoeAccent,
    this.visor = false,
    this.hatTrim,
    this.hairStyle,
    this.hairColor,
    this.face = CharacterFace.normal,
    this.pet,
    this.petColor,
    this.petAccent,
    this.scarf,
    this.scarfTrim,
    this.vest,
  });

  /// 머리 모양과 색입니다. 모양이 없으면 머리카락을 그리지 않고, 색이 없으면 짙은 갈색입니다.
  final HairStyle? hairStyle;
  final Color? hairColor;
  final CharacterFace face;

  /// 곁에 선 반려동물과 몸·포인트 색입니다.
  final CharacterPet? pet;
  final Color? petColor;
  final Color? petAccent;

  /// 목도리 색과 줄무늬 색, 패딩 조끼 색입니다(계절 의상).
  final Color? scarf;
  final Color? scarfTrim;
  final Color? vest;

  /// 모자 색입니다. [visor]면 윗부분이 뚫린 썬캡, [headband]면 머리띠로 그립니다.
  final Color? hat;

  /// 모자 테두리와 꼭대기 방울 색입니다(산타 모자처럼). 없으면 모자보다 조금 어두운 띠입니다.
  final Color? hatTrim;
  final bool headband;
  final bool visor;
  final Color? glasses;

  /// 상의 색입니다. [singlet]이면 소매 없는 러닝 싱글렛입니다.
  final Color? top;
  final bool singlet;
  final Color? bottom;
  final Color? sleeves;
  final Color? shoes;
  final Color? shoeAccent;

  static const none = CharacterOutfit();

  @override
  bool operator ==(Object other) =>
      other is CharacterOutfit &&
      other.hat == hat &&
      other.hatTrim == hatTrim &&
      other.hairStyle == hairStyle &&
      other.hairColor == hairColor &&
      other.face == face &&
      other.pet == pet &&
      other.petColor == petColor &&
      other.petAccent == petAccent &&
      other.scarf == scarf &&
      other.scarfTrim == scarfTrim &&
      other.vest == vest &&
      other.headband == headband &&
      other.visor == visor &&
      other.glasses == glasses &&
      other.top == top &&
      other.singlet == singlet &&
      other.bottom == bottom &&
      other.sleeves == sleeves &&
      other.shoes == shoes &&
      other.shoeAccent == shoeAccent;

  @override
  int get hashCode => Object.hashAll([
    hat,
    hatTrim,
    hairStyle,
    hairColor,
    face,
    pet,
    petColor,
    petAccent,
    scarf,
    scarfTrim,
    vest,
    headband,
    visor,
    glasses,
    top,
    singlet,
    bottom,
    sleeves,
    shoes,
    shoeAccent,
  ]);
}

/// 위에서 살짝 내려다본 흰색 3D 러너입니다. [yaw](라디안)만큼 돌려 모든 방향에서 그립니다.
/// 몸은 둥근 덩어리(구·타원체)를 3D 좌표에 놓고 돌린 뒤, 먼 것부터 그려 입체로 보이게 합니다.
class RunnerCharacterPainter extends CustomPainter {
  RunnerCharacterPainter({
    required this.yaw,
    this.outfit = CharacterOutfit.none,
    this.breath = 0,
    this.ground = true,
    this.cheer = 0,
    this.hop = 0,
  });

  final double yaw;
  final CharacterOutfit outfit;

  /// 0~1 숨쉬기(살짝 위아래로 움직임)입니다.
  final double breath;

  /// 발밑 그림자를 그릴지입니다.
  final bool ground;

  /// 0~1 만세 자세입니다. 1이면 두 팔을 V자로 번쩍 듭니다.
  final double cheer;

  /// 점프 높이(캐릭터 키 기준, 0이면 땅)입니다. 그림자는 땅에 남아 작아집니다.
  final double hop;

  static const _skin = Color(0xFFF6F8FC);
  static const _pitch = 0.16;

  @override
  void paint(Canvas canvas, Size size) {
    // 캐릭터 키(약 2.0)를 칸 높이에 맞춥니다.
    final scale = math.min(size.height / 2.25, size.width / 1.35);
    final ground0 = Offset(size.width / 2, size.height * 0.94);
    final origin = ground0 - Offset(0, hop * scale);
    final bob = math.sin(breath * math.pi * 2) * 0.012;
    final view = _View(yaw, _pitch, scale, origin);

    if (ground) {
      final shrink = 1 / (1 + hop * 2.5);
      final shadow = Rect.fromCenter(
        center: ground0 + Offset(0, -scale * 0.01),
        width: scale * 0.95 * shrink,
        height: scale * 0.22 * shrink,
      );
      canvas.drawOval(
        shadow,
        Paint()
          ..color = const Color(0x40102040)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, scale * 0.04),
      );
    }

    final parts = <_Part>[];
    void blob(
      _V center,
      double rx,
      double ry,
      double rz,
      Color color, {
      double gloss = 1,
      double bias = 0,
    }) => parts.add(_Blob(view, center, rx, ry, rz, color, gloss, bias));

    final o = outfit;
    final topColor = o.top ?? _skin;
    final sleeveTop = o.top != null && !o.singlet ? o.top! : _skin;
    final bottomColor = o.bottom ?? _skin;
    final up = bob;

    // 게임 캐릭터처럼 머리가 크고 몸은 동글동글, 팔다리는 짤막합니다.
    // 다리: 짧고 통통한 기둥. 윗부분은 반바지 색입니다.
    for (final side in [-1.0, 1.0]) {
      final hip = _V(0.15 * side, 0.44 + up * .5, 0);
      final ankle = _V(0.16 * side, 0.15, 0.01);
      _limb(parts, view, hip, ankle, 0.12, 0.11, bottomColor, (t) => t < 0.5);
      _limb(parts, view, hip, ankle, 0.12, 0.11, _skin, (t) => t >= 0.5);
      // 발(신발): 동그랗고 앞으로 살짝 긴 덩어리와 밑창.
      final shoe = o.shoes ?? _skin;
      blob(_V(0.17 * side, 0.09, 0.05), 0.13, 0.095, 0.17, shoe);
      if (o.shoes != null) {
        blob(
          _V(0.17 * side, 0.035, 0.055),
          0.135,
          0.035,
          0.175,
          o.shoeAccent ?? Colors.white,
          gloss: 0.4,
        );
      }
    }

    // 몸: 아래는 반바지, 위는 상의를 입은 동글한 콩 모양입니다.
    blob(_V(0, 0.50 + up, 0), 0.31, 0.16, 0.25, bottomColor);
    blob(_V(0, 0.70 + up, 0), 0.33, 0.27, 0.27, topColor, bias: 0.01);

    // 팔: 짤막한 팔과 동그란 손. 위는 상의 소매, 아래는 팔토시 색입니다.
    for (final side in [-1.0, 1.0]) {
      final shoulder = _V(0.29 * side, 0.84 + up, 0);
      // 만세(cheer)일수록 팔이 V자로 위로 올라갑니다.
      final wrist = _V(
        0.44 * side,
        0.60 + up,
        0.05,
      ).lerp(_V(0.66 * side, 1.02 + up, 0.06), cheer);
      _limb(
        parts,
        view,
        shoulder,
        wrist,
        0.095,
        0.085,
        sleeveTop,
        (t) => t < 0.4,
      );
      _limb(
        parts,
        view,
        shoulder,
        wrist,
        0.095,
        0.085,
        o.sleeves ?? _skin,
        (t) => t >= 0.4,
      );
      blob(
        _V(
          0.46 * side,
          0.55 + up,
          0.06,
        ).lerp(_V(0.71 * side, 1.07 + up, 0.07), cheer),
        0.1,
        0.1,
        0.1,
        _skin,
      );
    }

    // 계절 의상(패딩 조끼·목도리)은 몸 위에, 반려동물은 곁에 둡니다.
    final headY = 1.33 + up * 1.4;
    _addSeasonWear(parts, view, o, up);
    _addPet(parts, view, o);
    _addHairVolume(parts, view, o, headY);

    // 큰 머리(몸보다 큼).
    final head = _V(0, headY, 0.0);
    const headR = 0.56;
    parts.add(_Head(view, head, headR, o, up));

    // 먼 것부터 그립니다.
    parts.sort((a, b) => a.depth.compareTo(b.depth));
    for (final part in parts) {
      part.paint(canvas);
    }
  }

  void _limb(
    List<_Part> parts,
    _View view,
    _V from,
    _V to,
    double r0,
    double r1,
    Color color,
    bool Function(double t) include,
  ) {
    // 포함 구간(0~1)만 매끈한 원통(캡슐)으로 그립니다.
    double? start, end;
    for (var i = 0; i <= 20; i++) {
      final t = i / 20;
      if (!include(t)) continue;
      start ??= t;
      end = t;
    }
    if (start == null || end == null) return;
    parts.add(
      _Capsule(
        view,
        from.lerp(to, start),
        from.lerp(to, end),
        r0 + (r1 - r0) * start,
        r0 + (r1 - r0) * end,
        color,
      ),
    );
  }

  @override
  bool shouldRepaint(RunnerCharacterPainter old) =>
      old.yaw != yaw ||
      old.outfit != outfit ||
      old.breath != breath ||
      old.cheer != cheer ||
      old.hop != hop;
}

/// 3D 점입니다(x 오른쪽, y 위, z 앞쪽).
class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V lerp(_V b, double t) =>
      _V(x + (b.x - x) * t, y + (b.y - y) * t, z + (b.z - z) * t);
  _V operator +(_V b) => _V(x + b.x, y + b.y, z + b.z);
  _V scale(double k) => _V(x * k, y * k, z * k);
}

/// 돌리기(yaw)와 살짝 내려다보기(pitch) 후 화면 좌표로 옮깁니다.
class _View {
  _View(this.yaw, this.pitch, this.scale, this.origin);
  final double yaw, pitch, scale;
  final Offset origin;

  /// 돌린 뒤의 3D 좌표입니다(z가 클수록 화면 앞).
  _V turn(_V p) {
    final c = math.cos(yaw), s = math.sin(yaw);
    final x = p.x * c + p.z * s;
    final z = -p.x * s + p.z * c;
    final cp = math.cos(pitch), sp = math.sin(pitch);
    final y = p.y * cp - z * sp;
    final z2 = p.y * sp + z * cp;
    return _V(x, y, z2);
  }

  Offset screen(_V turned) =>
      origin + Offset(turned.x * scale, -turned.y * scale);
}

abstract class _Part {
  double get depth;
  void paint(Canvas canvas);
}

/// 빛을 받는 둥근 덩어리(타원체)입니다.
class _Blob extends _Part {
  _Blob(
    this.view,
    this.center,
    this.rx,
    this.ry,
    this.rz,
    this.color,
    this.gloss, [
    this.bias = 0,
    this.warmShade = false,
  ]) : turned = view.turn(center);

  final _View view;
  final _V center;
  final double rx, ry, rz;
  final Color color;
  final double gloss;

  /// 같은 깊이일 때 앞에 그릴 순서입니다(상의가 반바지 위로).
  final double bias;

  /// 그늘을 회색빛이 아니라 같은 색의 어두운 톤으로 칠합니다(머리카락처럼 색이 중요한 것).
  final bool warmShade;
  final _V turned;

  @override
  double get depth => turned.z + bias;

  @override
  void paint(Canvas canvas) {
    final c = math.cos(view.yaw).abs(), s = math.sin(view.yaw).abs();
    // 돌리면 옆 폭과 앞뒤 두께가 섞여 보입니다.
    final width = math.sqrt(rx * rx * c * c + rz * rz * s * s) * 2 * view.scale;
    final height = ry * 2 * view.scale;
    final at = view.screen(turned);
    final rect = Rect.fromCenter(center: at, width: width, height: height);
    final shade = warmShade
        ? Color.lerp(color, Colors.black, 0.22)!
        : Color.lerp(color, const Color(0xFF8C9BB3), 0.38)!;
    final deep = warmShade
        ? Color.lerp(color, Colors.black, 0.42)!
        : Color.lerp(color, const Color(0xFF6B7A94), 0.55)!;
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [
            Color.lerp(color, Colors.white, 0.55 * gloss)!,
            color,
            shade,
            deep,
          ],
          stops: const [0, 0.38, 0.82, 1],
        ).createShader(rect),
    );
  }
}

/// 팔·다리 같은 둥근 기둥입니다. 빛 쪽은 밝고 반대쪽은 그늘지게 칠합니다.
class _Capsule extends _Part {
  _Capsule(this.view, this.a, this.b, this.ra, this.rb, this.color)
    : ta = view.turn(a),
      tb = view.turn(b);

  final _View view;
  final _V a, b;
  final double ra, rb;
  final Color color;
  final _V ta, tb;

  @override
  double get depth => (ta.z + tb.z) / 2;

  @override
  void paint(Canvas canvas) {
    final pa = view.screen(ta), pb = view.screen(tb);
    final width = (ra + rb) * view.scale;
    var axis = pb - pa;
    if (axis.distance < 0.01) axis = const Offset(0, 1);
    var perp = Offset(-axis.dy, axis.dx) / axis.distance;
    // 빛(왼쪽 위) 쪽을 그라데이션 시작으로 둡니다.
    if (perp.dx > 0 || (perp.dx == 0 && perp.dy > 0)) perp = -perp;
    final mid = Offset.lerp(pa, pb, 0.5)!;
    final shade = Color.lerp(color, const Color(0xFF8C9BB3), 0.42)!;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..shader = ui.Gradient.linear(
        mid + perp * width / 2,
        mid - perp * width / 2,
        [Color.lerp(color, Colors.white, 0.5)!, color, shade],
        const [0.05, 0.45, 1],
      );
    canvas.drawLine(pa, pb, paint);
  }
}

/// 머리: 구에 눈·코·입·볼을 붙이고, 모자·선글라스를 씌웁니다. 얼굴은 앞을 볼 때만 보입니다.
class _Head extends _Part {
  _Head(this.view, this.center, this.r, this.outfit, this.up)
    : turned = view.turn(center);

  final _View view;
  final _V center;
  final double r;
  final CharacterOutfit outfit;
  final double up;
  final _V turned;

  @override
  double get depth => turned.z + 0.05;

  /// 머리 표면 위 점입니다. [lon]은 좌우(0이 정면), [lat]은 위아래 각도입니다.
  _V _surface(double lon, double lat, [double lift = 1]) => center.lerp(
    center +
        _V(
          math.sin(lon) * math.cos(lat),
          math.sin(lat),
          math.cos(lon) * math.cos(lat),
        ).scale(r * lift),
    1,
  );

  /// 표면 점이 앞을 향하는 정도(0 이하는 안 보임)와 화면 위치입니다.
  (double, Offset) _feature(double lon, double lat, [double lift = 1.0]) {
    final p = view.turn(_surface(lon, lat, lift));
    final facing = (p.z - turned.z) / (r * lift);
    return (facing, view.screen(p));
  }

  @override
  void paint(Canvas canvas) {
    final at = view.screen(turned);
    final radius = r * view.scale;
    final rect = Rect.fromCircle(center: at, radius: radius);
    const skin = RunnerCharacterPainter._skin;
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [
            Colors.white,
            skin,
            Color.lerp(skin, const Color(0xFF8C9BB3), 0.38)!,
            Color.lerp(skin, const Color(0xFF6B7A94), 0.55)!,
          ],
          stops: const [0, 0.38, 0.82, 1],
        ).createShader(rect),
    );

    final o = outfit;
    final unit = view.scale * r;

    // 머리카락 덮개는 얼굴 그림 아래에 깔고(앞머리가 이마만 덮음), 모자는 그 위에 씁니다.
    paintHair(canvas, at, radius);

    // 얼굴: 볼 → 눈 → 코 → 입. 옆으로 돌수록 납작해지고 뒤로 가면 사라집니다.
    void oval(double lon, double lat, double w, double h, Color color) {
      final (facing, p) = _feature(lon, lat);
      if (facing <= 0.05) return;
      canvas.drawOval(
        Rect.fromCenter(
          center: p,
          width: w * unit * facing.clamp(0.0, 1.0),
          height: h * unit,
        ),
        Paint()..color = color.withValues(alpha: color.a * facing.clamp(0, 1)),
      );
    }

    // 볼터치.
    for (final side in [-1.0, 1.0]) {
      oval(0.56 * side, -0.32, 0.26, 0.14, const Color(0x66FF8FA3));
    }
    if (o.glasses == null) {
      for (final side in [-1.0, 1.0]) {
        // 표정이 있으면 그 눈을 그립니다(윙크는 한쪽 눈만).
        if (o.face != CharacterFace.normal &&
            !(o.face == CharacterFace.wink && side < 0)) {
          paintExpressionEye(canvas, side, unit);
          continue;
        }
        // 크고 동그란 눈과 반짝임 두 개(게임 캐릭터처럼 또랑또랑하게).
        oval(0.3 * side, -0.1, 0.22, 0.31, const Color(0xFF1F2836));
        final (facing, p) = _feature(0.3 * side - 0.055, -0.02);
        if (facing > 0.2) {
          canvas.drawCircle(p, unit * 0.055, Paint()..color = Colors.white);
        }
        final (facing2, q) = _feature(0.3 * side + 0.045, -0.18);
        if (facing2 > 0.2) {
          canvas.drawCircle(q, unit * 0.025, Paint()..color = Colors.white);
        }
      }
    }
    // 작은 코.
    oval(0, -0.25, 0.06, 0.04, const Color(0xFFE8B4A6));
    // 입: 작은 웃는 곡선.
    final (mouthFacing, _) = _feature(0, -0.38);
    if (mouthFacing > 0.1) {
      final left = _feature(-0.11, -0.34).$2;
      final mid = _feature(0, -0.41).$2;
      final right = _feature(0.11, -0.34).$2;
      canvas.drawPath(
        Path()
          ..moveTo(left.dx, left.dy)
          ..quadraticBezierTo(
            2 * mid.dx - (left.dx + right.dx) / 2,
            2 * mid.dy - (left.dy + right.dy) / 2,
            right.dx,
            right.dy,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = unit * 0.045
          ..color = const Color(0xFF1F2836)
              .withValues(alpha: mouthFacing.clamp(0, 1)),
      );
    }

    // 선글라스: 두 렌즈와 다리. 앞을 볼 때 보입니다.
    if (o.glasses case final lens?) {
      for (final side in [-1.0, 1.0]) {
        oval(0.3 * side, -0.09, 0.4, 0.32, lens);
        final (facing, p) = _feature(0.24 * side, 0.0);
        if (facing > 0.2) {
          canvas.drawCircle(
            p,
            unit * 0.035,
            Paint()..color = Colors.white.withValues(alpha: 0.7),
          );
        }
      }
      final (facing, a) = _feature(-0.11, -0.05);
      final b = _feature(0.11, -0.05).$2;
      if (facing > 0.1) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = lens
            ..strokeWidth = unit * 0.05,
        );
      }
    }

    // 모자: 머리 위를 덮는 둥근 덮개와 앞쪽 챙(썬캡은 덮개 없이 띠와 챙), 머리띠는 이마의 띠.
    if (o.hat case final color?) {
      final band = Paint()
        ..color = o.hatTrim ?? Color.lerp(color, Colors.black, 0.12)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.16
        ..strokeCap = StrokeCap.round;
      // 이마 둘레 띠: 보이는 앞쪽 반만 그립니다.
      final ring = Path();
      var started = false;
      // 모자 덮개를 자를 높이: 보이는 띠 중 가장 아래 지점(어느 방향에서 봐도 틈이 없게).
      var cut = double.negativeInfinity;
      for (var i = 0; i <= 36; i++) {
        final lon = -math.pi + i * math.pi * 2 / 36;
        final (facing, p) = _feature(lon, o.headband ? 0.34 : 0.36, 1.02);
        if (facing < -0.05) {
          started = false;
          continue;
        }
        cut = math.max(cut, p.dy);
        if (!started) {
          ring.moveTo(p.dx, p.dy);
          started = true;
        } else {
          ring.lineTo(p.dx, p.dy);
        }
      }
      if (!o.headband && !o.visor) {
        // 덮개: 머리 윗부분을 모자 색 원으로 덮고 위쪽만 남깁니다.
        canvas.save();
        canvas.clipRect(
          Rect.fromLTRB(
            rect.left - radius,
            rect.top - radius,
            rect.right + radius,
            cut + unit * 0.02,
          ),
        );
        final dome = rect.inflate(unit * 0.04);
        canvas.drawOval(
          dome,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.6),
              colors: [
                Color.lerp(color, Colors.white, 0.35)!,
                color,
                Color.lerp(color, Colors.black, 0.3)!,
              ],
              stops: const [0, 0.5, 1],
            ).createShader(dome),
        );
        canvas.restore();
      }
      canvas.drawPath(ring, band..color = o.headband ? color : band.color);
      if (!o.headband) {
        // 챙: 이마 앞에서 앞으로 튀어나온 납작한 판(돌리면 함께 돕니다).
        final base = center + _V(0, r * 0.34, 0);
        final tip = view.turn(base + _V(0, -0.03, r * 1.75));
        final left = view.turn(base + _V(-r * 0.82, 0, r * 0.75));
        final right = view.turn(base + _V(r * 0.82, 0, r * 0.75));
        final mid = view.turn(base + _V(0, 0.02, r * 0.95));
        final brim = Path()
          ..moveTo(view.screen(left).dx, view.screen(left).dy)
          ..quadraticBezierTo(
            view.screen(tip).dx,
            view.screen(tip).dy,
            view.screen(right).dx,
            view.screen(right).dy,
          )
          ..quadraticBezierTo(
            view.screen(mid).dx,
            view.screen(mid).dy,
            view.screen(left).dx,
            view.screen(left).dy,
          );
        // 챙 밑 그늘이 얼굴에 살짝 드리워집니다.
        canvas.drawPath(
          brim.shift(Offset(0, unit * 0.08)),
          Paint()
            ..color = const Color(0x33203048)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.05),
        );
        canvas.drawPath(
          brim,
          Paint()..color = Color.lerp(color, Colors.black, 0.18)!,
        );
      }
      // 산타 모자처럼 테두리 색이 있으면 꼭대기에 동그란 방울을 답니다.
      if (o.hatTrim case final trim? when !o.headband && !o.visor) {
        final top = view.screen(view.turn(center + _V(0, r * 1.04, 0)));
        final ball = Rect.fromCircle(center: top, radius: unit * 0.17);
        canvas.drawOval(
          ball,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.45),
              colors: [Colors.white, trim, Color.lerp(trim, Colors.black, .2)!],
              stops: const [0, 0.55, 1],
            ).createShader(ball),
        );
      }
    }
  }
}

/// 캐릭터 뒤 배경: 하늘과 관중석 아래로 운동장 트랙이 원근감 있게 펼쳐집니다.
class TrackBackgroundPainter extends CustomPainter {
  const TrackBackgroundPainter({this.dark = false});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.42;
    // 하늘.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF1B2A4A), Color(0xFF3A5A8C)]
              : const [Color(0xFF8EC5FF), Color(0xFFDCEEFF)],
        ).createShader(Rect.fromLTWH(0, 0, w, horizon)),
    );
    // 멀리 관중석과 잔디.
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - h * 0.07, w, h * 0.07),
      Paint()..color = dark ? const Color(0xFF2B3B55) : const Color(0xFFB7C6DA),
    );
    for (var i = 0; i < 14; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
          i * w / 14 + 2,
          horizon - h * 0.065,
          w / 14 - 4,
          h * 0.012,
        ),
        Paint()
          ..color = dark ? const Color(0xFF3B4E6E) : const Color(0xFFD5DFEC),
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h * 0.06),
      Paint()..color = dark ? const Color(0xFF2E6B47) : const Color(0xFF6CC48A),
    );
    // 트랙: 아래로 갈수록 넓어지는 붉은 우레탄 바닥과 흰 레인 선.
    final top = horizon + h * 0.06;
    canvas.drawRect(
      Rect.fromLTWH(0, top, w, h - top),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF8A3B2C), Color(0xFF6E2E22)]
              : const [Color(0xFFE2735A), Color(0xFFC85A43)],
        ).createShader(Rect.fromLTWH(0, top, w, h - top)),
    );
    final lane = Paint()
      ..color = Colors.white.withValues(alpha: dark ? 0.55 : 0.85)
      ..strokeWidth = 2;
    const lanes = 7;
    final vanish = Offset(w * 0.5, horizon - h * 0.25);
    for (var i = 0; i <= lanes; i++) {
      final x = -w * 0.6 + i * (w * 2.2) / lanes;
      final bottom = Offset(x, h);
      // 아래 끝에서 소실점 쪽으로 가다가 트랙 윗선에서 멈춥니다.
      final t = (h - top) / (h - vanish.dy);
      final upper = Offset.lerp(bottom, vanish, t)!;
      canvas.drawLine(bottom, upper, lane);
    }
    canvas.drawLine(
      Offset(0, top),
      Offset(w, top),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(TrackBackgroundPainter old) => old.dark != dark;
}

/// 트랙 배경 위에 선 캐릭터입니다. 좌우로 밀면 돌아가고, 손을 떼면 관성으로 조금 더 돌다 멈춥니다.
class RunnerCharacterStage extends StatefulWidget {
  const RunnerCharacterStage({
    this.outfit = CharacterOutfit.none,
    this.height = 260,
    this.interactive = true,
    this.initialYaw = -0.35,
    super.key,
  });

  final CharacterOutfit outfit;
  final double height;
  final bool interactive;
  final double initialYaw;

  @override
  State<RunnerCharacterStage> createState() => _RunnerCharacterStageState();
}

class _RunnerCharacterStageState extends State<RunnerCharacterStage>
    with TickerProviderStateMixin {
  late double _yaw = widget.initialYaw;
  double _velocity = 0;
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _spin = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() => _yaw = _spin.value));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _breath.stop();
    } else {
      _breathe();
    }
  }

  /// 숨쉬기는 몇 번만 하고 쉽니다(배터리 절약). 만지면 다시 숨을 쉽니다.
  void _breathe() {
    if (_breath.isAnimating || MediaQuery.disableAnimationsOf(context)) return;
    _breath.repeat(count: 4);
  }

  @override
  void dispose() {
    _breath.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails details) {
    _spin.stop();
    _breathe();
    setState(() => _yaw -= details.delta.dx * 0.018);
  }

  void _release(DragEndDetails details) {
    _velocity = -details.velocity.pixelsPerSecond.dx * 0.018;
    if (_velocity.abs() < 0.2 || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    // 던진 속도만큼 조금 더 돌다가 천천히 멈춥니다.
    _spin.value = _yaw;
    _spin.animateWith(FrictionSimulation(0.08, _yaw, _velocity));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stage = SizedBox(
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: TrackBackgroundPainter(dark: dark)),
          Padding(
            padding: EdgeInsets.only(top: widget.height * 0.06),
            child: AnimatedBuilder(
              animation: _breath,
              builder: (context, _) => CustomPaint(
                key: const ValueKey('runner-character'),
                painter: RunnerCharacterPainter(
                  yaw: _yaw,
                  outfit: widget.outfit,
                  breath: _breath.value,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!widget.interactive) return stage;
    return Semantics(
      label: '내 러너 캐릭터. 좌우로 밀어 돌려 볼 수 있어요.',
      child: GestureDetector(
        onHorizontalDragUpdate: _drag,
        onHorizontalDragEnd: _release,
        // 두 번 누르면 정면으로 돌아옵니다.
        onDoubleTap: () {
          _spin.stop();
          setState(() => _yaw = widget.initialYaw);
        },
        child: stage,
      ),
    );
  }
}
