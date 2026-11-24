import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 앱을 켜자마자 보이는 첫 화면입니다.
/// 폰의 시작 화면(파란 바탕 가운데 발자국 120)과 같은 그림으로 이어받아 끊김 없이 보이고,
/// 발자국 아래 '뜀터' 글자가 나타났다가 오른쪽으로 '슝' 하고 달려 나간 뒤 [child]로 넘어갑니다.
class BrandIntro extends StatefulWidget {
  const BrandIntro({required this.child, super.key});

  final Widget child;

  /// 첫 화면 전체 시간입니다. 끝나기 조금 전부터 [child]를 깔고 부드럽게 넘깁니다.
  static const duration = Duration(milliseconds: 1500);

  /// 폰 시작 화면의 발자국 크기(dp)와 같아야 합니다(android splash_icon.xml, iOS LaunchImage).
  static const footprintSize = 120.0;
  static const blue = Color(0xFF3182F6);
  static const _asset = 'assets/branding/splash_footprints.png';

  /// 앱 시작 전(폰 시작 화면이 떠 있는 동안) 발자국 그림을 미리 풀어 둡니다.
  /// 그래야 첫 화면 첫 장면부터 발자국이 보여 폰 시작 화면과 끊김 없이 이어집니다.
  static ui.Image? _footprints;
  static Future<void> preload() async {
    try {
      final data = await rootBundle.load(_asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _footprints = (await codec.getNextFrame()).image;
    } catch (_) {
      // 미리 풀지 못하면 화면에서 불러옵니다.
    }
  }

  @override
  State<BrandIntro> createState() => _BrandIntroState();
}

class _BrandIntroState extends State<BrandIntro>
    with SingleTickerProviderStateMixin {
  late final _intro = AnimationController(
    vsync: this,
    duration: BrandIntro.duration,
  )..addStatusListener(_onStatus);

  /// 이 시점부터 다음 화면을 아래에 깔아 둡니다(글자가 화면 밖으로 나간 뒤).
  static const _handOff = 0.82;
  bool _showChild = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _intro.addListener(() {
      if (!_showChild && _intro.value >= _handOff) {
        setState(() => _showChild = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _done) return;
    // 동작 줄이기 설정이면 글자만 잠깐 보여주고 넘어갑니다.
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 0.3;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _finish();
      });
    } else {
      _intro.forward();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finish();
  }

  void _finish() {
    if (_done) return;
    setState(() {
      _showChild = true;
      _done = true;
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showChild) widget.child,
        AnimatedBuilder(
          animation: _intro,
          builder: (context, _) {
            final t = _intro.value;
            // 마지막에 첫 화면을 서서히 걷어 다음 화면(러너 로딩)으로 넘깁니다.
            final fade = 1 - ((t - _handOff) / (1 - _handOff)).clamp(0.0, 1.0);
            return IgnorePointer(
              child: Opacity(
                opacity: fade,
                child: _IntroScene(t: t),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _IntroScene extends StatelessWidget {
  const _IntroScene({required this.t});

  final double t;

  // 시간표(0~1): 글자 등장 → 잠깐 멈춤 → 뒤로 살짝 움츠렸다가 → 오른쪽으로 슝.
  static const _appearEnd = 0.2;
  static const _crouchStart = 0.42;
  static const _dashStart = 0.52;
  static const _dashEnd = 0.8;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final appear = Curves.easeOutCubic.transform(
      (t / _appearEnd).clamp(0.0, 1.0),
    );
    final crouch = Curves.easeInOut.transform(
      ((t - _crouchStart) / (_dashStart - _crouchStart)).clamp(0.0, 1.0),
    );
    final dash = Curves.easeInCubic.transform(
      ((t - _dashStart) / (_dashEnd - _dashStart)).clamp(0.0, 1.0),
    );
    // 달려 나가는 거리: 화면 오른쪽 밖까지.
    final travel = size.width * 0.75 + 120;
    final text = Text(
      '뜀터',
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        height: 1,
        decoration: TextDecoration.none,
      ),
    );
    // Material로 감싸 앱 글꼴(기본 글자 모양)을 씁니다.
    return Material(
      color: BrandIntro.blue,
      child: Stack(
        children: [
          // 발자국: 폰 시작 화면과 같은 자리·크기라서 넘어가는 순간이 보이지 않습니다.
          Center(
            child: switch (BrandIntro._footprints) {
              final image? => RawImage(
                image: image,
                width: BrandIntro.footprintSize,
                height: BrandIntro.footprintSize,
                filterQuality: FilterQuality.medium,
              ),
              null => Image.asset(
                BrandIntro._asset,
                width: BrandIntro.footprintSize,
                height: BrandIntro.footprintSize,
                gaplessPlayback: true,
              ),
            },
          ),
          Align(
            alignment: Alignment.center,
            child: Transform.translate(
              offset: Offset(
                // 출발 전 뒤로 살짝 움츠렸다가 오른쪽으로 빠르게 달려 나갑니다.
                -10 * crouch * (1 - dash) + travel * dash,
                BrandIntro.footprintSize / 2 + 34 + 10 * (1 - appear),
              ),
              child: Opacity(
                opacity: appear,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // 달리는 동안 글자 뒤로 바람 선이 길게 남습니다.
                    if (dash > 0)
                      Positioned(
                        right: 74,
                        child: CustomPaint(
                          size: const Size(10, 30),
                          painter: _SpeedLines(dash),
                        ),
                      ),
                    Transform(
                      alignment: Alignment.center,
                      // 움츠릴 땐 옆으로 눌리고, 달릴 땐 앞으로 기울어집니다.
                      transform: Matrix4.identity()
                        ..setEntry(0, 1, -0.28 * dash)
                        ..scaleByDouble(
                          1 - 0.08 * crouch * (1 - dash) + 0.12 * dash,
                          1,
                          1,
                          1,
                        ),
                      child: text,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 글자 뒤(왼쪽)로 뻗는 흰 바람 선 세 줄입니다. 빨라질수록 길고 진해집니다.
class _SpeedLines extends CustomPainter {
  _SpeedLines(this.dash);

  final double dash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;
    // 가운데 줄이 가장 길고, 위·아래 줄은 조금 짧습니다.
    const rows = [(-10.0, 0.7), (0.0, 1.0), (10.0, 0.8)];
    final grow = math.min(1.0, dash * 2);
    for (final (y, share) in rows) {
      final length = 110 * share * grow;
      paint.shader =
          LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.85),
            ],
          ).createShader(
            Rect.fromLTWH(size.width - length, 0, math.max(1, length), 1),
          );
      canvas.drawLine(
        Offset(size.width - length, size.height / 2 + y),
        Offset(size.width, size.height / 2 + y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpeedLines old) => old.dash != dash;
}
