part of 'runner_character.dart';

// 캐릭터 꾸미기 확장(머리 모양·머리색·표정·반려동물·계절 의상)을 그립니다.
// runner_character.dart와 같은 라이브러리라서 같은 3D 도구(_V·_Blob·_Part·_View)를 씁니다.

const _defaultHair = Color(0xFF5B3A29);

// ── 계절 의상 ─────────────────────────────────────────────────────────────

/// 패딩 조끼(몸통을 한 겹 더 감쌈)와 목도리(목에 둘러 앞으로 늘어짐)를 그립니다.
void _addSeasonWear(
  List<_Part> parts,
  _View view,
  CharacterOutfit o,
  double up,
) {
  void blob(
    _V c,
    double rx,
    double ry,
    double rz,
    Color color, {
    double gloss = 0.7,
    double bias = 0,
  }) => parts.add(_Blob(view, c, rx, ry, rz, color, gloss, bias));

  if (o.vest case final vest?) {
    // 통통한 패딩: 몸통보다 조금 크게, 가로 누빔 줄 두 개와 가운데 지퍼 줄을 더합니다.
    blob(_V(0, 0.71 + up, 0), 0.365, 0.285, 0.305, vest, bias: 0.02);
    final seam = Color.lerp(vest, Colors.black, .32)!;
    for (final y in [0.82, 0.62]) {
      blob(_V(0, y + up, 0), 0.372, 0.012, 0.312, seam, gloss: 0, bias: 0.021);
    }
    blob(
      _V(0, 0.66 + up, 0.3),
      0.012,
      0.15,
      0.012,
      seam,
      gloss: 0,
      bias: 0.021,
    );
  }
  if (o.scarf case final scarf?) {
    final trim = o.scarfTrim ?? Colors.white;
    // 목을 한 바퀴 두르고(턱 아래로 보임) 줄무늬를 넣은 뒤, 한쪽이 가슴 앞으로 길게 늘어집니다.
    blob(_V(0, 0.79 + up, 0), 0.4, 0.1, 0.34, scarf, bias: 0.03);
    blob(
      _V(0, 0.76 + up, 0.0),
      0.408,
      0.022,
      0.348,
      trim,
      gloss: 0.3,
      bias: 0.031,
    );
    blob(_V(0, 0.745 + up, 0.17), 0.3, 0.085, 0.19, scarf, bias: 0.032);
    final top = _V(0.17, 0.72 + up, 0.31);
    final bottom = _V(0.2, 0.48 + up, 0.33);
    parts.add(_Capsule(view, top, bottom, 0.085, 0.075, scarf));
    parts.add(
      _Capsule(
        view,
        top.lerp(bottom, 0.72),
        top.lerp(bottom, 0.8),
        0.083,
        0.08,
        trim,
      ),
    );
  }
}

// ── 반려동물 ──────────────────────────────────────────────────────────────

/// 캐릭터 곁(화면 오른쪽 앞)에 서 있는 반려동물입니다. 몸을 돌려도 같이 도는 3D 덩어리입니다.
void _addPet(List<_Part> parts, _View view, CharacterOutfit o) {
  final kind = o.pet;
  if (kind == null) return;
  final body = o.petColor ?? Colors.white;
  final accent = o.petAccent ?? const Color(0xFF3B2A20);
  const eyeColor = Color(0xFF1F2836);
  const px = 0.74, pz = 0.2;

  void blob(
    double dx,
    double y,
    double dz,
    double rx,
    double ry,
    double rz,
    Color color, {
    double gloss = 0.8,
  }) => parts.add(
    _Blob(view, _V(px + dx, y, pz + dz), rx, ry, rz, color, gloss, 0),
  );

  void eyes(double y, double front, double spread, [double size = 0.024]) {
    for (final side in [-1.0, 1.0]) {
      blob(
        spread * side,
        y,
        front,
        size,
        size * 1.2,
        size,
        eyeColor,
        gloss: 0.1,
      );
    }
  }

  switch (kind) {
    case CharacterPet.chick:
      // 노란 병아리: 동그란 몸, 작은 머리, 주황 부리와 발.
      blob(0, 0.17, 0, 0.17, 0.16, 0.17, body);
      blob(0, 0.37, 0.02, 0.125, 0.12, 0.12, body);
      blob(0, 0.355, 0.15, 0.04, 0.026, 0.05, accent, gloss: 0.4);
      blob(0, 0.405, 0.1, 0.03, 0.06, 0.03, body); // 머리 깃
      for (final side in [-1.0, 1.0]) {
        blob(
          0.17 * side,
          0.18,
          0.0,
          0.05,
          0.1,
          0.1,
          Color.lerp(body, Colors.orange, .25)!,
        );
        blob(0.06 * side, 0.03, 0.04, 0.045, 0.025, 0.07, accent, gloss: 0.3);
      }
      eyes(0.395, 0.105, 0.055);
    case CharacterPet.dog:
      // 강아지: 긴 몸, 늘어진 귀, 하얀 주둥이와 검은 코.
      blob(0, 0.2, 0, 0.14, 0.14, 0.23, body);
      blob(0, 0.37, 0.2, 0.135, 0.13, 0.13, body);
      blob(
        0,
        0.335,
        0.31,
        0.07,
        0.055,
        0.06,
        Color.lerp(body, Colors.white, .6)!,
      );
      blob(0, 0.355, 0.365, 0.027, 0.02, 0.02, eyeColor, gloss: 0.2);
      for (final side in [-1.0, 1.0]) {
        blob(0.125 * side, 0.36, 0.19, 0.05, 0.12, 0.06, accent); // 늘어진 귀
        blob(0.07 * side, 0.05, 0.14, 0.05, 0.05, 0.05, body); // 앞발
        blob(0.07 * side, 0.05, -0.14, 0.05, 0.05, 0.05, body); // 뒷발
      }
      blob(0, 0.3, -0.27, 0.04, 0.04, 0.1, accent); // 꼬리
      eyes(0.405, 0.285, 0.055);
    case CharacterPet.cat:
      // 고양이: 뾰족한 귀, 길게 올라간 꼬리, 작은 분홍 코.
      blob(0, 0.19, 0, 0.125, 0.13, 0.21, body);
      blob(0, 0.36, 0.19, 0.13, 0.12, 0.12, body);
      for (final side in [-1.0, 1.0]) {
        blob(0.08 * side, 0.5, 0.18, 0.045, 0.075, 0.03, body); // 뾰족한 귀
        blob(
          0.08 * side,
          0.495,
          0.2,
          0.025,
          0.045,
          0.015,
          const Color(0xFFF4A6B8),
          gloss: 0.3,
        );
        blob(0.065 * side, 0.05, 0.12, 0.045, 0.05, 0.05, body);
        blob(0.065 * side, 0.05, -0.12, 0.045, 0.05, 0.05, body);
      }
      blob(
        0,
        0.33,
        0.295,
        0.022,
        0.016,
        0.016,
        const Color(0xFFF08FA6),
        gloss: 0.3,
      );
      for (var i = 0; i < 4; i++) {
        blob(
          0.02 * i,
          0.26 + i * 0.1,
          -0.22 - i * 0.02,
          0.035,
          0.07,
          0.035,
          i.isOdd ? accent : body,
        );
      }
      eyes(0.385, 0.265, 0.05, 0.022);
    case CharacterPet.bunny:
      // 토끼: 하얀 몸, 길쭉한 귀, 동그란 꼬리.
      blob(0, 0.18, 0, 0.14, 0.14, 0.17, body);
      blob(0, 0.37, 0.07, 0.115, 0.11, 0.11, body);
      for (final side in [-1.0, 1.0]) {
        blob(0.055 * side, 0.58, 0.04, 0.034, 0.15, 0.03, body);
        blob(0.055 * side, 0.58, 0.06, 0.018, 0.115, 0.014, accent, gloss: 0.3);
        blob(0.07 * side, 0.04, 0.1, 0.05, 0.04, 0.06, body);
      }
      blob(0, 0.205, -0.19, 0.06, 0.06, 0.06, Colors.white);
      blob(
        0,
        0.345,
        0.17,
        0.022,
        0.016,
        0.016,
        const Color(0xFFF08FA6),
        gloss: 0.3,
      );
      eyes(0.395, 0.155, 0.045);
  }
}

// ── 머리카락 ──────────────────────────────────────────────────────────────

/// 머리 모양의 부피(뒷머리·옆머리·묶은 머리·번·곱슬 뭉치)를 3D 덩어리로 더합니다.
/// 머리 윗부분의 머리카락 덮개와 앞머리는 [_Head]가 그립니다.
void _addHairVolume(
  List<_Part> parts,
  _View view,
  CharacterOutfit o,
  double headY,
) {
  final style = o.hairStyle;
  if (style == null) return;
  final color = o.hairColor ?? _defaultHair;
  const tieColor = Color(0xFFF0508C);

  void blob(
    double x,
    double y,
    double z,
    double rx,
    double ry,
    double rz, {
    Color? paint,
    double gloss = 0.6,
  }) => parts.add(
    _Blob(view, _V(x, y, z), rx, ry, rz, paint ?? color, gloss, 0, true),
  );

  switch (style) {
    case HairStyle.bob:
      // 턱선까지 내려오는 단발: 양옆과 뒤를 둥글게 감쌉니다.
      for (final side in [-1.0, 1.0]) {
        blob(0.5 * side, headY - 0.14, -0.04, 0.16, 0.36, 0.38);
      }
      blob(0, headY - 0.16, -0.3, 0.5, 0.42, 0.26);
    case HairStyle.ponytail:
      // 뒤통수 위에서 묶은 꼬리가 아래로 늘어집니다.
      blob(
        0,
        headY + 0.2,
        -0.56,
        0.065,
        0.065,
        0.065,
        paint: tieColor,
        gloss: 0.4,
      );
      blob(0, headY + 0.1, -0.66, 0.13, 0.17, 0.12);
      blob(0, headY - 0.12, -0.72, 0.125, 0.23, 0.115);
      blob(0, headY - 0.4, -0.7, 0.09, 0.2, 0.09);
    case HairStyle.pigtails:
      // 양옆 귀 위에서 묶은 두 갈래.
      for (final side in [-1.0, 1.0]) {
        blob(
          0.6 * side,
          headY + 0.06,
          -0.12,
          0.06,
          0.06,
          0.06,
          paint: tieColor,
          gloss: 0.4,
        );
        blob(0.68 * side, headY - 0.1, -0.12, 0.13, 0.2, 0.13);
        blob(0.7 * side, headY - 0.38, -0.1, 0.1, 0.22, 0.1);
      }
    case HairStyle.bun:
      // 정수리의 동그란 번.
      blob(0, headY + 0.6, -0.16, 0.22, 0.2, 0.22);
      blob(
        0,
        headY + 0.5,
        -0.16,
        0.26,
        0.04,
        0.26,
        paint: tieColor,
        gloss: 0.3,
      );
    case HairStyle.curly:
      // 곱슬곱슬 뭉치가 머리 둘레를 감쌉니다(앞머리 쪽은 비워 둡니다).
      const r = 0.56;
      for (var i = 0; i < 12; i++) {
        final lon = i * math.pi * 2 / 12;
        if (math.cos(lon) > 0.6) continue;
        final lat = 0.62;
        blob(
          math.sin(lon) * math.cos(lat) * r,
          headY + math.sin(lat) * r,
          math.cos(lon) * math.cos(lat) * r,
          0.17,
          0.17,
          0.17,
        );
      }
      for (var i = 0; i < 9; i++) {
        final lon = 0.9 + i * (math.pi * 2 - 1.8) / 8;
        const lat = 0.1;
        blob(
          math.sin(lon) * math.cos(lat) * (r + 0.03),
          headY + math.sin(lat) * r,
          math.cos(lon) * math.cos(lat) * (r + 0.03),
          0.15,
          0.16,
          0.15,
        );
      }
      blob(0, headY + r, -0.04, 0.2, 0.17, 0.2);
  }
}

extension _HeadHair on _Head {
  /// 머리 윗부분을 덮는 머리카락 덮개(앞머리 포함)를 그립니다.
  /// 머리선은 앞(이마)이 높고 옆·뒤로 갈수록 내려가며, 어느 방향에서 봐도 이어지게 그립니다.
  void paintHair(Canvas canvas, Offset at, double radius) {
    final style = outfit.hairStyle;
    if (style == null) return;
    final color = outfit.hairColor ?? _defaultHair;
    // (앞, 옆, 뒤)에서의 머리선 높이(라디안)입니다. 클수록 이마가 드러납니다.
    final (front, side, back) = switch (style) {
      HairStyle.bob => (0.30, -0.12, -0.8),
      HairStyle.ponytail => (0.32, 0.02, -0.12),
      HairStyle.pigtails => (0.32, 0.05, -0.05),
      HairStyle.bun => (0.34, 0.05, 0.0),
      HairStyle.curly => (0.4, 0.12, 0.0),
    };
    double smooth(double t) => t * t * (3 - 2 * t);
    double hairline(double lon) {
      var l = lon % (math.pi * 2);
      if (l > math.pi) l -= math.pi * 2;
      l = l.abs();
      if (l <= math.pi / 2) {
        return front + (side - front) * smooth(l / (math.pi / 2));
      }
      return side + (back - side) * smooth((l - math.pi / 2) / (math.pi / 2));
    }

    // 보이는 쪽 반(왼쪽 가장자리 → 오른쪽 가장자리)의 머리선 점들입니다.
    final center = -view.yaw;
    const steps = 28;
    final line = <Offset>[
      for (var i = 0; i <= steps; i++)
        _feature(
          center - math.pi / 2 + i * math.pi / steps,
          hairline(center - math.pi / 2 + i * math.pi / steps),
          1.03,
        ).$2,
    ];
    final cap = radius * 1.03;
    final a0 = math.atan2(line.last.dy - at.dy, line.last.dx - at.dx);
    var a1 = math.atan2(line.first.dy - at.dy, line.first.dx - at.dx);
    if (a1 > a0) a1 -= math.pi * 2;
    final path = Path()..moveTo(line.first.dx, line.first.dy);
    for (final point in line.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path
      ..arcTo(Rect.fromCircle(center: at, radius: cap), a0, a1 - a0, false)
      ..close();
    final rect = Rect.fromCircle(center: at, radius: cap);
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.55),
          radius: 1.05,
          colors: [
            Color.lerp(color, Colors.white, 0.34)!,
            color,
            Color.lerp(color, Colors.black, 0.38)!,
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  /// 표정에 따라 한쪽 눈을 그립니다(보통 눈은 [_Head]가 직접 그림).
  /// [side]는 -1(왼쪽)·1(오른쪽)이고 [unit]은 머리 반지름의 화면 크기입니다.
  void paintExpressionEye(Canvas canvas, double side, double unit) {
    const ink = Color(0xFF1F2836);
    final face = outfit.face;

    // ^ 모양(웃는 눈)이나 ⌒ 모양(윙크)의 호를 그립니다.
    void arc({required bool up}) {
      const lat = -0.1;
      final left = _feature(0.3 * side - 0.13, lat).$2;
      final mid = _feature(0.3 * side, lat + (up ? 0.17 : -0.17));
      final right = _feature(0.3 * side + 0.13, lat).$2;
      if (mid.$1 <= 0.1) return;
      canvas.drawPath(
        Path()
          ..moveTo(left.dx, left.dy)
          ..quadraticBezierTo(
            2 * mid.$2.dx - (left.dx + right.dx) / 2,
            2 * mid.$2.dy - (left.dy + right.dy) / 2,
            right.dx,
            right.dy,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = unit * 0.075
          ..color = ink.withValues(alpha: mid.$1.clamp(0.0, 1.0)),
      );
    }

    // 눈 자리에 도형(하트·별)을 그립니다. 옆으로 돌수록 납작해집니다.
    void shape(Path Function(double size) build, Color fill, Color? edge) {
      final (facing, p) = _feature(0.3 * side, -0.08);
      if (facing <= 0.05) return;
      final s = unit * 0.15;
      canvas
        ..save()
        ..translate(p.dx, p.dy)
        ..scale(facing.clamp(0.0, 1.0), 1);
      final path = build(s);
      canvas.drawPath(path, Paint()..color = fill);
      if (edge != null) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * 0.03
            ..strokeJoin = StrokeJoin.round
            ..color = edge,
        );
      }
      canvas.restore();
    }

    switch (face) {
      case CharacterFace.wink:
        // 오른쪽 눈만 감습니다(⌒).
        arc(up: false);
      case CharacterFace.happy:
        arc(up: true);
      case CharacterFace.heart:
        shape(_heartPath, const Color(0xFFFF4D7A), const Color(0xFFD62A5B));
      case CharacterFace.star:
        shape(_starPath, const Color(0xFFFFD43B), const Color(0xFFE0A100));
      case CharacterFace.normal:
        break;
    }
  }
}

Path _heartPath(double s) => Path()
  ..moveTo(0, s * 0.95)
  ..cubicTo(-s * 1.7, s * 0.1, -s * 0.95, -s * 1.05, 0, -s * 0.35)
  ..cubicTo(s * 0.95, -s * 1.05, s * 1.7, s * 0.1, 0, s * 0.95)
  ..close();

Path _starPath(double s) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final radius = i.isEven ? s * 1.25 : s * 0.55;
    final angle = -math.pi / 2 + i * math.pi / 5;
    final x = math.cos(angle) * radius;
    final y = math.sin(angle) * radius;
    i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
  }
  return path..close();
}
