import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 앱을 켤 때의 로딩 화면입니다.
/// 위에서 내려다본 입체 흰색 러너가 화면 오른쪽 아래에서 왼쪽 위로 곧게 달려가며,
/// 지나간 자리에 발자국이 잠깐 남았다가 사라집니다. 왼쪽 위 모서리 앞 결승선 테이프를 끊고 나면
/// [FootprintLoaderState.firstStride]가 끝나 앱이 켜집니다. 앱이 더 늦게 준비되면 한 번 더 달립니다.
class FootprintLoader extends StatefulWidget {
  const FootprintLoader({super.key});

  @override
  State<FootprintLoader> createState() => FootprintLoaderState();
}

class FootprintLoaderState extends State<FootprintLoader>
    with SingleTickerProviderStateMixin {
  /// 한 번 달리는 시간입니다(출발 → 결승선 통과 → 화면 밖).
  static const runDuration = Duration(milliseconds: 2200);

  /// 결승선 테이프가 끊기고 잠깐 펄럭인 뒤 앱을 켭니다.
  static const finishDelay = Duration(milliseconds: 1950);

  final _firstStride = Completer<void>();
  Future<void> get firstStride => _firstStride.future;
  Timer? _timer;

  late final _run = AnimationController(vsync: this, duration: runDuration);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _timer = Timer(finishDelay, _firstStride.complete);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _run.stop();
    } else if (!_run.isAnimating) {
      _run.repeat();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_firstStride.isCompleted) _firstStride.complete();
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '불러오는 중',
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: RunnerIntroPainter(
          _run,
          still: MediaQuery.disableAnimationsOf(context),
        ),
      ),
    ),
  );
}

/// 러너·발자국·결승선을 그립니다. [progress]는 0(출발)~1(한 바퀴 끝)입니다.
class RunnerIntroPainter extends CustomPainter {
  RunnerIntroPainter(this.progress, {this.still = false})
    : super(repaint: progress);

  final Animation<double> progress;
  final bool still;

  /// 한 바퀴 중 러너가 출발점에서 화면 밖(왼쪽 위)까지 가는 비율입니다. 나머지는 테이프가 펄럭이는 시간입니다.
  static const runShare = 0.86;

  /// 경로 위 결승선의 위치(0~1)입니다. 왼쪽 위 모서리 조금 앞입니다.
  static const finishAt = 0.8;

  /// 발자국이 남아 있는 시간(한 바퀴 비율)입니다.
  static const printLife = 0.22;

  // 빛은 왼쪽 위에서 비춥니다. 그림자는 오른쪽 아래로 떨어집니다.
  static const _light = Offset(-0.7071, -0.7071);
  static const _white = Color(0xFFFFFFFF);
  static const _shade = Color(0xFFC9D6E8);
  static const _deepShade = Color(0xFF9FB2CC);
  static const _ribbon = Color(0xFFFFD43B);
  static const _ribbonShade = Color(0xFFE0A800);

  // 밑창 모양은 앱 아이콘과 같이 앞꿈치와 뒤꿈치 사이에 사선 틈을 둡니다.
  static final _sole = Path()
    ..moveTo(-5, 0)
    ..cubicTo(-5, -7, -3, -12, 1, -12)
    ..cubicTo(5, -12, 7, -8, 5, -3)
    ..close()
    ..moveTo(-5, 1.7)
    ..lineTo(4.5, -1.3)
    ..cubicTo(2, 4, 2, 9, -2, 9)
    ..cubicTo(-5, 9, -6, 6, -5, 1.7)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = (size.shortestSide / 390).clamp(0.55, 1.4);
    final reach = 46 * scale;
    // 오른쪽 아래 모서리 밖에서 출발해 왼쪽 위 모서리 밖으로 곧게 달려 나갑니다.
    final start = Offset(size.width + reach, size.height + reach);
    final end = Offset(-reach, -reach);
    final route = end - start;
    final forward = route / route.distance;
    final side = Offset(-forward.dy, forward.dx);
    final heading = route.direction + math.pi / 2;
    final strideLength = 58 * scale;
    final steps = (route.distance / strideLength).floor();

    // 결승선 위치: 테이프 양쪽 기둥이 화면 안에 들어오도록 왼쪽 위 모서리에서 조금 떨어뜨립니다.
    final half = 70 * scale;
    final margin = 28 * scale;
    final needX = margin + half * side.dx.abs();
    final needY = margin + half * side.dy.abs();
    final finish = math.min(
      finishAt,
      math.min((start.dx - needX) / -route.dx, (start.dy - needY) / -route.dy),
    );
    final t = still ? finish * runShare * 0.82 : progress.value;
    final travelled = (t / runShare).clamp(0.0, 1.0);
    final runnerAt = start + route * travelled;
    // 한 걸음마다 다리가 반 바퀴씩 흔들립니다.
    final phase = travelled * steps * math.pi;
    final crossedAt = finish * runShare;

    _paintFinish(
      canvas,
      start + route * finish,
      forward,
      side,
      half,
      scale,
      t,
      crossedAt,
    );
    if (!still) {
      _paintPrints(canvas, start, route, side, heading, steps, scale, t);
    }
    if (travelled < 1) {
      _paintRunner(canvas, runnerAt, heading, phase, scale);
    }
  }

  void _paintPrints(
    Canvas canvas,
    Offset start,
    Offset route,
    Offset side,
    double heading,
    int steps,
    double scale,
    double t,
  ) {
    final paint = Paint();
    for (var step = 0; step < steps; step++) {
      // 발이 땅에 닿는 순간(다리가 가장 멀리 뻗었을 때) 그 자리에 발자국을 남깁니다.
      final along = (step + 0.5) / steps;
      final placed = along * runShare;
      final age = t - placed;
      if (age < 0 || age > printLife) continue;
      final fade = (age / printLife).clamp(0.0, 1.0);
      final left = step.isEven;
      final at = start + route * along + side * (left ? -7.0 : 7.0) * scale;
      paint.color = _white.withValues(alpha: 0.55 * (1 - fade) * (1 - fade));
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(heading);
      canvas.scale(scale * (left ? -1.25 : 1.25), scale * 1.25);
      canvas.drawPath(_sole, paint);
      canvas.restore();
    }
  }

  /// 결승선: 양쪽 기둥과 노란 테이프. 러너가 지나가면 가운데가 끊어져 양쪽으로 날리며 늘어집니다.
  void _paintFinish(
    Canvas canvas,
    Offset center,
    Offset forward,
    Offset side,
    double half,
    double scale,
    double t,
    double crossedAt,
  ) {
    final posts = [center - side * half, center + side * half];
    final broken = t >= crossedAt;
    final u = broken
        ? ((t - crossedAt) / (1 - crossedAt)).clamp(0.0, 1.0)
        : 0.0;
    final burst = Curves.easeOutCubic.transform(u);

    // 기둥 그림자와 기둥(위에서 본 둥근 기둥 꼭대기).
    for (final post in posts) {
      canvas.drawCircle(
        post + const Offset(4, 5) * scale,
        6 * scale,
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale),
      );
      canvas.drawCircle(
        post,
        6 * scale,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.5, -0.5),
            colors: const [_white, _deepShade],
          ).createShader(Rect.fromCircle(center: post, radius: 6 * scale)),
      );
    }

    final tape = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5 * scale;
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5 * scale
      ..color = const Color(0x2E000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * scale);

    if (!broken) {
      // 러너가 다가오면 테이프가 살짝 앞으로 밀립니다.
      final push = ((t - (crossedAt - 0.06)) / 0.06).clamp(0.0, 1.0);
      final middle = center + forward * 10 * scale * push;
      final path = Path()
        ..moveTo(posts[0].dx, posts[0].dy)
        ..quadraticBezierTo(middle.dx, middle.dy, posts[1].dx, posts[1].dy);
      canvas.drawPath(path.shift(const Offset(3, 4) * scale), shadow);
      tape.shader = LinearGradient(
        colors: const [_ribbonShade, _ribbon, _ribbonShade],
      ).createShader(Rect.fromPoints(posts[0], posts[1]));
      canvas.drawPath(path, tape);
      return;
    }

    // 끊어진 두 조각: 끝이 러너를 따라 앞으로 날렸다가 기둥 쪽으로 늘어지며 펄럭입니다.
    for (final (index, post) in posts.indexed) {
      final outward = index == 0 ? -1.0 : 1.0;
      final flutter = math.sin(u * math.pi * 5) * (1 - u) * 6 * scale;
      final tip =
          center +
          forward * (26 * burst - 10 * u * u) * scale +
          side * outward * (18 + 34 * burst) * scale +
          side * flutter;
      final bend =
          Offset.lerp(post, tip, 0.5)! +
          forward * (12 * burst) * scale +
          side * outward * -6 * scale;
      final path = Path()
        ..moveTo(post.dx, post.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, tip.dx, tip.dy);
      canvas.drawPath(path.shift(const Offset(3, 4) * scale), shadow);
      tape.shader = LinearGradient(colors: const [_ribbonShade, _ribbon])
          .createShader(Rect.fromPoints(post, tip));
      canvas.drawPath(path, tape);
    }
  }

  /// 위에서 내려다본 입체 러너입니다. 머리·어깨·팔·다리를 둥근 덩어리로 그리고
  /// 왼쪽 위에서 오는 빛으로 밝은 면과 그늘, 땅에 떨어진 그림자를 줍니다.
  void _paintRunner(
    Canvas canvas,
    Offset at,
    double heading,
    double phase,
    double scale,
  ) {
    final swing = math.sin(phase);
    // 발이 땅을 찰 때마다 몸이 살짝 떠오릅니다(위에서 보면 조금 커지고 그림자가 멀어짐).
    final bounce = math.sin(phase).abs();
    final lift = 1 + 0.05 * bounce;
    // 화면 기준 빛 방향을 러너 기준으로 돌립니다.
    final light = Offset(
      _light.dx * math.cos(-heading) - _light.dy * math.sin(-heading),
      _light.dx * math.sin(-heading) + _light.dy * math.cos(-heading),
    );
    final highlight = Alignment(light.dx * 0.6, light.dy * 0.6);

    // 땅 그림자: 오른쪽 아래로 떨어지고 뛰어오를수록 멀어지고 흐려집니다.
    final shadowShift = const Offset(9, 12) * scale * (1 + 0.6 * bounce);
    canvas.save();
    canvas.translate(at.dx + shadowShift.dx, at.dy + shadowShift.dy);
    canvas.rotate(heading);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 64 * scale,
        height: 84 * scale,
      ),
      Paint()
        ..color = Color.fromRGBO(10, 30, 80, 0.22 - 0.06 * bounce)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * scale),
    );
    canvas.restore();

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(heading);
    // 캐릭터는 화면에서 잘 보이도록 크게 그립니다.
    canvas.scale(scale * lift * 1.7);

    Paint limb(double width, Color color) => Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // 위에서 보면 다리는 몸 아래에서 앞뒤로 번갈아 나옵니다. 앞으로 나간 발은 밝고,
    // 뒤로 찬 발은 몸 그늘에 들어가 조금 어둡습니다. 무릎은 바깥으로 살짝 굽습니다.
    for (final side in [-1.0, 1.0]) {
      final reach = swing * side;
      final hip = Offset(4.5 * side, 2);
      final foot = hip + Offset(1.5 * side, -17 * reach + 2);
      final knee =
          Offset.lerp(hip, foot, 0.5)! + Offset(2.5 * side, reach > 0 ? -1 : 2);
      final color = Color.lerp(_white, _shade, reach < 0 ? 0.6 : 0.15)!;
      final leg = Path()
        ..moveTo(hip.dx, hip.dy)
        ..quadraticBezierTo(knee.dx, knee.dy, foot.dx, foot.dy);
      canvas.drawPath(leg, limb(5.5, color));
      // 신발: 발끝 쪽으로 길쭉한 타원(밑창 색을 살짝 어둡게).
      canvas.drawOval(
        Rect.fromCenter(
          center: foot + const Offset(0, -2.5),
          width: 6.5,
          height: 10,
        ),
        Paint()..color = Color.lerp(color, _deepShade, 0.35)!,
      );
    }

    // 상체는 걸음과 반대로 살짝 비틉니다(달릴 때 어깨가 엇갈리듯).
    canvas.save();
    canvas.rotate(-0.2 * swing);

    // 팔: 어깨에서 다리와 반대로 앞뒤로 흔들고 팔꿈치를 바깥으로 굽힙니다.
    for (final side in [-1.0, 1.0]) {
      final reach = -swing * side;
      final shoulder = Offset(14.5 * side, 1);
      final elbow = shoulder + Offset(2.5 * side, -7 * reach + 2.5);
      final hand = shoulder + Offset(0.5 * side, -13 * reach - 1);
      final color = Color.lerp(_white, _shade, reach < 0 ? 0.55 : 0.1)!;
      final arm = Path()
        ..moveTo(shoulder.dx, shoulder.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(hand.dx, hand.dy);
      canvas.drawPath(arm, limb(4.5, color));
      canvas.drawCircle(hand, 2.8, Paint()..color = color);
    }

    // 어깨·등: 옆으로 넓고 앞뒤로 얇은 타원. 빛 쪽이 밝고 반대쪽이 그늘집니다.
    final torso = Rect.fromCenter(
      center: const Offset(0, 1.5),
      width: 32,
      height: 13,
    );
    canvas.drawOval(
      torso,
      Paint()
        ..shader = RadialGradient(
          center: highlight,
          radius: 0.95,
          colors: const [_white, _white, _shade, _deepShade],
          stops: const [0, 0.3, 0.78, 1],
        ).createShader(torso),
    );
    canvas.restore();

    // 머리: 어깨 위에 올라간 구. 가장자리를 살짝 어둡게 해 어깨와 구분하고 하이라이트를 줍니다.
    final head = Rect.fromCircle(center: const Offset(0, -1.5), radius: 7);
    canvas.drawCircle(
      head.center + const Offset(0.8, 1.2),
      7.6,
      Paint()
        ..color = const Color(0x33203A66)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    canvas.drawOval(
      head,
      Paint()
        ..shader = RadialGradient(
          center: highlight,
          radius: 1,
          colors: const [_white, _white, _shade, _deepShade],
          stops: const [0, 0.35, 0.8, 1],
        ).createShader(head),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(RunnerIntroPainter old) =>
      old.still != still || old.progress != progress;
}
