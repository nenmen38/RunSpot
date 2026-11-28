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

/// 끝으로 갈수록 가늘어지는 머리 한 가닥(다발)입니다. 3D 점들을 따라 부드러운 곡선으로 그리고,
/// 빛 쪽은 밝게·반대쪽은 같은 색의 어두운 톤으로 칠한 뒤 윤기 한 줄을 얹습니다.
class _HairLock extends _Part {
  _HairLock(
    this.view,
    this.points,
    this.radii,
    this.color, [
    this.bias = 0,
    this.soft = 0,
  ]) : turned = [for (final p in points) view.turn(p)];

  final _View view;
  final List<_V> points;
  final List<double> radii;
  final Color color;
  final double bias;

  /// 0~1. 클수록 명암 차가 줄어 옆 다발과 매끄럽게 섞입니다(단발처럼 한 덩어리로 보일 때).
  final double soft;
  final List<_V> turned;

  @override
  double get depth =>
      turned.fold(0.0, (sum, p) => sum + p.z) / turned.length + bias;

  @override
  void paint(Canvas canvas) {
    final pts = [for (final p in turned) view.screen(p)];
    final n = pts.length;
    final widths = [for (final r in radii) r * view.scale];
    final left = <Offset>[], right = <Offset>[];
    for (var i = 0; i < n; i++) {
      var tangent = pts[math.min(i + 1, n - 1)] - pts[math.max(i - 1, 0)];
      if (tangent.distance < 0.001) tangent = const Offset(0, 1);
      final normal = Offset(-tangent.dy, tangent.dx) / tangent.distance;
      left.add(pts[i] + normal * widths[i]);
      right.add(pts[i] - normal * widths[i]);
    }
    // 가장자리 점들 사이를 중간점 곡선으로 이어 각지지 않게 합니다.
    void smooth(Path path, List<Offset> edge) {
      for (var i = 1; i < edge.length - 1; i++) {
        final mid = Offset.lerp(edge[i], edge[i + 1], 0.5)!;
        path.quadraticBezierTo(edge[i].dx, edge[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(edge.last.dx, edge.last.dy);
    }

    final path = Path()..moveTo(left.first.dx, left.first.dy);
    smooth(path, left);
    path.arcToPoint(
      right.last,
      radius: Radius.circular(math.max(widths.last, 0.5)),
      clockwise: false,
    );
    smooth(path, right.reversed.toList());
    path
      ..arcToPoint(
        left.first,
        radius: Radius.circular(math.max(widths.first, 0.5)),
        clockwise: false,
      )
      ..close();

    var axis = pts.last - pts.first;
    if (axis.distance < 0.01) axis = const Offset(0, 1);
    var perp = Offset(-axis.dy, axis.dx) / axis.distance;
    // 빛(왼쪽 위) 쪽에서 그라데이션이 시작되게 합니다.
    if (perp.dx > 0 || (perp.dx == 0 && perp.dy > 0)) perp = -perp;
    final wide = widths.reduce(math.max);
    final mid = Offset.lerp(pts.first, pts.last, 0.5)!;
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          mid + perp * wide,
          mid - perp * wide,
          [
            Color.lerp(color, Colors.white, 0.28 * (1 - soft))!,
            color,
            Color.lerp(color, Colors.black, 0.36 * (1 - soft * 0.6))!,
          ],
          const [0.0, 0.45, 1.0],
        ),
    );
    // 가운데보다 살짝 빛 쪽으로 가는 윤기 한 줄.
    final sheen = Path()
      ..moveTo(
        pts.first.dx + perp.dx * widths.first * 0.35,
        pts.first.dy + perp.dy * widths.first * 0.35,
      );
    for (var i = 1; i < n - 1; i++) {
      final p = pts[i] + perp * widths[i] * 0.35;
      sheen.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      sheen,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(wide * 0.22, 0.6)
        ..color = Colors.white.withValues(alpha: 0.16 * (1 - soft)),
    );
  }
}

/// 세 점(시작·꺾임·끝)을 지나는 부드러운 곡선 위의 점들입니다.
List<_V> _curve(_V a, _V b, _V c, _V d, [int steps = 10]) => [
  for (var i = 0; i <= steps; i++)
    () {
      final t = i / steps, u = 1 - t;
      return a.scale(u * u * u) +
          b.scale(3 * u * u * t) +
          c.scale(3 * u * t * t) +
          d.scale(t * t * t);
    }(),
];

/// 뿌리 → 가운데 → 끝 굵기를 부드럽게 잇습니다.
List<double> _taper(int count, double root, double middle, double tip) => [
  for (var i = 0; i < count; i++)
    () {
      final t = i / (count - 1);
      final w = t < 0.5
          ? root + (middle - root) * math.sin(t * math.pi)
          : middle + (tip - middle) * (1 - math.cos((t - 0.5) * math.pi));
      return w;
    }(),
];

/// 머리 모양의 부피(옆·뒷머리 다발, 묶은 머리, 번, 곱슬, 남자 머리의 볼륨·삐죽 머리)를 3D로 더합니다.
/// 머리 표면을 덮는 머리카락(앞머리·결·윤기)은 [_Head]가 그립니다.
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
  const r = 0.56;

  void blob(
    double x,
    double y,
    double z,
    double rx,
    double ry,
    double rz, {
    Color? paint,
    double gloss = 0.45,
    double bias = 0,
  }) => parts.add(
    _Blob(view, _V(x, y, z), rx, ry, rz, paint ?? color, gloss, bias, true),
  );

  /// 머리 표면 위(lift배 떨어진) 점입니다. 턱선 아래로는 곧게 늘어뜨립니다.
  _V onHead(double lon, double lat, double lift) {
    const hangFrom = -0.2;
    final l = math.max(lat, hangFrom);
    final p = _V(
      math.sin(lon) * math.cos(l) * r * lift,
      headY + math.sin(l) * r * lift,
      math.cos(lon) * math.cos(l) * r * lift,
    );
    return lat >= hangFrom ? p : p + _V(0, (lat - hangFrom) * r, 0);
  }

  /// 머리를 따라 흐르는 다발 하나를 더합니다. 끝은 [curl]만큼 안쪽으로 말립니다.
  void lock(
    double lon0,
    double lat0,
    double lon1,
    double lat1, {
    double lift = 1.07,
    double root = 0.1,
    double middle = 0.14,
    double tip = 0.06,
    double curl = 0.0,
    double flare = 0.0,
    double bias = 0,
    double soft = 0,
  }) {
    const steps = 10;
    final points = [
      for (var i = 0; i <= steps; i++)
        () {
          final t = i / steps;
          final lon = lon0 + (lon1 - lon0) * t;
          final lat = lat0 + (lat1 - lat0) * t;
          return onHead(
            lon,
            lat,
            lift + 0.03 * math.sin(t * math.pi) + flare * t - curl * t * t * t,
          );
        }(),
    ];
    parts.add(
      _HairLock(
        view,
        points,
        _taper(points.length, root, middle, tip),
        color,
        bias,
        soft,
      ),
    );
  }

  /// 머리 위쪽에 볼륨을 더하는 덩어리(얼굴 앞으로는 나오지 않게 머리 뒤에 둠).
  void crownVolume({double height = 0.2, double size = 0.6}) =>
      blob(0, headY + height, -0.04, size, 0.5, size, gloss: 0.3, bias: -0.3);

  switch (style) {
    case HairStyle.bob:
      // 턱선까지 오는 단발: 얼굴 옆부터 뒤까지 다발이 이어져 둥글게 감싸고 끝이 안으로 말립니다.
      for (var i = 0; i < 23; i++) {
        final lon = math.pi * (0.38 + i * (2 - 0.76) / 22);
        lock(
          lon,
          1.0,
          lon,
          -0.8,
          lift: 0.96,
          flare: 0.14,
          root: 0.08,
          middle: 0.1,
          tip: 0.09,
          curl: 0.1,
          soft: 0.85,
          bias: -0.25,
        );
      }
    case HairStyle.ponytail:
      // 뒤통수 위에서 묶어 아래로 흘러내리는 꼬리.
      final tie = _V(0, headY + 0.22, -0.56);
      blob(tie.x, tie.y, tie.z, 0.07, 0.07, 0.07, paint: tieColor, gloss: 0.4);
      final tail = _curve(
        tie + const _V(0, 0, -0.04),
        _V(0, headY + 0.2, -0.95),
        _V(0, headY - 0.3, -0.82),
        _V(0.04, headY - 0.66, -0.66),
      );
      parts.add(
        _HairLock(view, tail, _taper(tail.length, 0.1, 0.16, 0.035), color),
      );
    case HairStyle.pigtails:
      // 양옆 귀 위에서 묶은 두 갈래가 바깥으로 살짝 휘며 내려옵니다.
      for (final side in [-1.0, 1.0]) {
        final tie = _V(0.58 * side, headY + 0.06, -0.14);
        blob(
          tie.x,
          tie.y,
          tie.z,
          0.065,
          0.065,
          0.065,
          paint: tieColor,
          gloss: 0.4,
        );
        final tail = _curve(
          tie + _V(0.04 * side, 0, 0),
          _V(0.86 * side, headY - 0.02, -0.16),
          _V(0.84 * side, headY - 0.36, -0.12),
          _V(0.74 * side, headY - 0.62, -0.08),
        );
        parts.add(
          _HairLock(view, tail, _taper(tail.length, 0.085, 0.135, 0.03), color),
        );
      }
    case HairStyle.bun:
      // 정수리의 동그란 번과 그 둘레를 감은 머리끈.
      blob(0, headY + 0.6, -0.14, 0.22, 0.19, 0.22);
      blob(
        -0.05,
        headY + 0.66,
        -0.08,
        0.1,
        0.07,
        0.1,
        paint: Color.lerp(color, Colors.white, 0.1),
      );
      blob(
        0,
        headY + 0.5,
        -0.14,
        0.25,
        0.04,
        0.25,
        paint: tieColor,
        gloss: 0.3,
      );
    case HairStyle.curly:
      // 촘촘한 작은 곱슬이 머리 둘레를 감싸고, 뒤에 볼륨 덩어리가 틈을 메웁니다.
      blob(0, headY + 0.1, -0.12, 0.58, 0.52, 0.56, gloss: 0.15, bias: -0.35);
      for (final (lat, count, size, skipFront) in const [
        (0.95, 7, 0.12, 2.0),
        (0.6, 14, 0.12, 0.6),
        (0.22, 16, 0.115, 0.3),
        (-0.2, 13, 0.11, -0.45),
      ]) {
        for (var i = 0; i < count; i++) {
          final lon = (i + (lat > 0.5 ? 0.5 : 0)) * math.pi * 2 / count;
          if (math.cos(lon) > skipFront && lat < 0.9) continue;
          final p = onHead(lon, lat, 1.04);
          blob(p.x, p.y, p.z, size, size * 0.95, size, gloss: 0.25);
        }
      }
    case HairStyle.short:
      // 짧은 머리: 위로 살짝 볼륨만 더합니다.
      crownVolume(height: 0.16, size: 0.6);
    case HairStyle.dandy:
      // 댄디컷: 위 볼륨과 한쪽으로 쓸어 넘긴 앞머리 다발.
      crownVolume(height: 0.18, size: 0.61);
      for (final (offset, end) in const [
        (-0.36, 0.42),
        (-0.12, 0.36),
        (0.12, 0.4),
        (0.36, 0.5),
      ]) {
        lock(
          -0.7 + offset,
          1.2,
          0.1 + offset * 0.9,
          end,
          lift: 1.02,
          root: 0.07,
          middle: 0.1,
          tip: 0.03,
          bias: 0.06,
          soft: 0.55,
        );
      }
    case HairStyle.spiky:
      // 삐죽머리: 정수리와 앞쪽으로 뾰족한 다발이 솟습니다.
      crownVolume(height: 0.12, size: 0.59);
      // 앞줄(이마 위) → 가운데 줄 → 뒷줄 순으로 짧고 도톰한 다발이 겹쳐 솟습니다.
      final spikes = <(double, double, double)>[
        for (var i = 0; i < 5; i++) (-0.8 + i * 0.4, 0.72, 1.3),
        for (var i = 0; i < 4; i++) (-0.9 + i * 0.6, 1.05, 1.36),
        for (final lon in const [-2.4, -1.6, 1.6, 2.4, 3.14]) (lon, 0.62, 1.2),
      ];
      for (final (lon, lat, reach) in spikes) {
        final base = onHead(lon, lat, 0.97);
        final bend = onHead(lon, lat + 0.22, (1 + reach) / 2);
        final out = onHead(lon * 0.92, lat + 0.42, reach);
        final points = _curve(base, base.lerp(bend, 0.7), bend, out, 6);
        parts.add(
          _HairLock(
            view,
            points,
            _taper(points.length, 0.15, 0.1, 0.014),
            color,
            0.04,
            0.45,
          ),
        );
      }
  }
}

extension _HeadHair on _Head {
  /// 머리 표면을 덮는 머리카락(앞머리 포함)과 결·윤기를 그립니다.
  /// 머리선은 앞(이마)이 높고 옆·뒤로 갈수록 내려가며, 어느 방향에서 봐도 이어지게 그립니다.
  void paintHair(Canvas canvas, Offset at, double radius) {
    final style = outfit.hairStyle;
    if (style == null) return;
    final color = outfit.hairColor ?? _defaultHair;
    // (앞, 옆, 뒤)에서의 머리선 높이(라디안)입니다. 클수록 이마가 드러납니다.
    // 묶거나 긴 머리는 뒤통수를 목덜미까지 덮고, 남자 머리는 뒷머리를 짧게 칩니다.
    final (front, side, back) = switch (style) {
      HairStyle.bob => (0.28, -0.3, -0.9),
      HairStyle.ponytail => (0.32, -0.35, -0.85),
      HairStyle.pigtails => (0.3, -0.3, -0.85),
      HairStyle.bun => (0.34, -0.35, -0.85),
      HairStyle.curly => (0.42, 0.1, -0.5),
      HairStyle.short => (0.5, 0.14, -0.5),
      HairStyle.dandy => (0.4, 0.08, -0.52),
      HairStyle.spiky => (0.48, 0.12, -0.48),
    };
    double smooth(double t) => t * t * (3 - 2 * t);
    double hairline(double lon) {
      var l = lon % (math.pi * 2);
      if (l > math.pi) l -= math.pi * 2;
      final signed = l;
      l = l.abs();
      if (l <= math.pi / 2) {
        final base = front + (side - front) * smooth(l / (math.pi / 2));
        final faceWeight = math.cos(l).clamp(0.0, 1.0);
        // 앞머리 끝을 살짝 물결지게 해 일자로 잘린 느낌을 없앱니다.
        final fringe = switch (style) {
          // 댄디컷은 한쪽(오른쪽)으로 쓸어 넘겨 이마가 비스듬히 드러납니다.
          HairStyle.dandy => 0.16 * math.sin(signed) * faceWeight,
          HairStyle.short || HairStyle.spiky => 0.02 * math.sin(signed * 9),
          _ => 0.035 * math.sin(signed * 7) * faceWeight,
        };
        return base + fringe;
      }
      return side + (back - side) * smooth((l - math.pi / 2) / (math.pi / 2));
    }

    // 보이는 쪽 반(왼쪽 가장자리 → 오른쪽 가장자리)의 머리선 점들입니다.
    final center = -view.yaw;
    const steps = 36;
    final lons = [
      for (var i = 0; i <= steps; i++)
        center - math.pi / 2 + i * math.pi / steps,
    ];
    final line = [
      for (final lon in lons) _feature(lon, hairline(lon), 1.03).$2,
    ];
    final cap = radius * 1.03;
    final a0 = math.atan2(line.last.dy - at.dy, line.last.dx - at.dx);
    var a1 = math.atan2(line.first.dy - at.dy, line.first.dx - at.dx);
    if (a1 > a0) a1 -= math.pi * 2;
    final path = Path()..moveTo(line.first.dx, line.first.dy);
    for (var i = 1; i < line.length - 1; i++) {
      final mid = Offset.lerp(line[i], line[i + 1], 0.5)!;
      path.quadraticBezierTo(line[i].dx, line[i].dy, mid.dx, mid.dy);
    }
    path
      ..lineTo(line.last.dx, line.last.dy)
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
            Color.lerp(color, Colors.white, 0.3)!,
            color,
            Color.lerp(color, Colors.black, 0.36)!,
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );

    canvas
      ..save()
      ..clipPath(path);
    final unit = radius;
    // 머리 결: 정수리에서 머리선 쪽으로 흐르는 옅은 선들.
    for (var i = 0; i < 16; i++) {
      final lon = center - math.pi / 2 + (i + 0.5) * math.pi / 16;
      final end = hairline(lon) + 0.04;
      final strand = Path();
      var started = false;
      var facingSum = 0.0;
      for (var k = 0; k <= 8; k++) {
        final lat = 1.45 + (end - 1.45) * k / 8;
        final (facing, p) = _feature(
          lon + 0.06 * math.sin(k / 8 * math.pi),
          lat,
          1.03,
        );
        facingSum += facing;
        if (!started) {
          strand.moveTo(p.dx, p.dy);
          started = true;
        } else {
          strand.lineTo(p.dx, p.dy);
        }
      }
      final alpha = (facingSum / 9).clamp(0.0, 1.0) * 0.22;
      if (alpha <= 0.01) continue;
      canvas.drawPath(
        strand,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = unit * 0.022
          ..color = Color.lerp(
            color,
            Colors.black,
            0.45,
          )!.withValues(alpha: alpha),
      );
    }
    // 윤기 띠: 정수리 아래로 둥글게 도는 밝은 띠(빛 쪽이 더 밝음).
    for (var i = 0; i < steps; i++) {
      final lon = lons[i];
      final (facing, p) = _feature(lon, 0.78, 1.03);
      final (_, q) = _feature(lons[i + 1], 0.78, 1.03);
      if (facing <= 0) continue;
      final light = (0.55 - 0.45 * math.sin(lon + view.yaw)).clamp(0.0, 1.0);
      canvas.drawLine(
        p,
        q,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = unit * 0.16
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.05)
          ..color = Colors.white.withValues(alpha: 0.16 * facing * light),
      );
    }
    canvas.restore();
    // 머리선 가장자리를 살짝 어둡게 그어 이마와 자연스럽게 구분합니다.
    final edge = Path()..moveTo(line.first.dx, line.first.dy);
    for (var i = 1; i < line.length - 1; i++) {
      final mid = Offset.lerp(line[i], line[i + 1], 0.5)!;
      edge.quadraticBezierTo(line[i].dx, line[i].dy, mid.dx, mid.dy);
    }
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.02
        ..color = Color.lerp(color, Colors.black, 0.3)!.withValues(alpha: 0.5),
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
