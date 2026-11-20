import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 앱 아이콘의 갈라진 밑창이 번갈아 찍히는 로딩 표시입니다.
class FootprintLoader extends StatefulWidget {
  const FootprintLoader({super.key});

  @override
  State<FootprintLoader> createState() => FootprintLoaderState();
}

class FootprintLoaderState extends State<FootprintLoader>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(seconds: 1);
  final _firstStride = Completer<void>();
  Future<void> get firstStride => _firstStride.future;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _timer = Timer(_duration, _firstStride.complete);
    });
  }

  late final _stride = AnimationController(vsync: this, duration: _duration);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _stride.stop();
    } else if (!_stride.isAnimating) {
      _stride.repeat();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_firstStride.isCompleted) _firstStride.complete();
    _stride.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '불러오는 중',
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _Footprints(_stride, MediaQuery.disableAnimationsOf(context)),
      ),
    ),
  );
}

class _Footprints extends CustomPainter {
  _Footprints(this.stride, this.still) : super(repaint: stride);

  final Animation<double> stride;
  final bool still;

  // 브랜드 아이콘과 같이 앞꿈치와 뒤꿈치 사이에 사선 틈을 둡니다.
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
    final paint = Paint();
    if (size.isEmpty) return;
    final scale = math.min(1.0, size.shortestSide / 160);
    final margin = 40 * scale;
    final start = Offset(size.width - margin, size.height - margin);
    final end = Offset(margin, margin);
    final route = end - start;
    final sideways = Offset(-route.dy, route.dx) / route.distance;
    final steps = (route.distance / 116).round().clamp(4, 10);
    final middle = (steps - 1) ~/ 2;
    // 화면 양 끝의 착지점은 고정하고, 중간 걸음만 좌우로 엇갈리게 합니다.
    for (var step = 0; step < steps; step++) {
      final progress = step / (steps - 1);
      final age = stride.value - progress * 0.73;
      if (still ? step != middle && step != middle + 1 : age < 0 || age >= 0.48)
        continue;
      final fade = still ? 0.0 : ((age - 0.13) / 0.35).clamp(0.0, 1.0);
      final impact = still || age > 0.10 ? 0.0 : math.sin(math.pi * age / 0.10);
      final left = step.isEven;
      paint.color = Colors.white.withValues(alpha: 1 - fade);
      canvas.save();
      final stagger = step == 0 || step == steps - 1
          ? 0.0
          : (left ? -8.0 : 8.0);
      final landing = start + route * progress + sideways * stagger * scale;
      canvas.translate(landing.dx, landing.dy);
      canvas.rotate(route.direction + math.pi / 2);
      canvas.scale(scale);
      canvas.scale(
        (left ? -3.0 : 3.0) * (1 + impact * 0.15),
        3.0 * (1 - impact * 0.12),
      );
      canvas.drawPath(_sole, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Footprints old) =>
      old.still != still || old.stride != stride;
}
