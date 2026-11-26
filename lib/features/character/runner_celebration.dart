import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../monetization/coin_frames.dart';
import 'character_outfit.dart';
import 'runner_character.dart';
import 'runner_character_card.dart';

/// 러닝을 마치면 내 캐릭터가 트랙 위에서 깡충 뛰며 만세를 하고 색종이가 흩날립니다.
class RunnerCelebration extends StatefulWidget {
  const RunnerCelebration({
    this.outfit = CharacterOutfit.none,
    this.message = '오늘도 완주했어요!',
    this.height = 210,
    super.key,
  });

  final CharacterOutfit outfit;
  final String message;
  final double height;

  /// 지갑에서 입은 옷을 읽어 축하합니다(옷을 바꾸면 바로 반영).
  static Widget forWallet(
    WalletController? wallet, {
    String message = '오늘도 완주했어요!',
    Key? key,
  }) => wallet == null
      ? RunnerCelebration(message: message, key: key)
      : ListenableBuilder(
          key: key,
          listenable: wallet,
          builder: (context, _) => RunnerCelebration(
            outfit: characterOutfit(wornCharacterItems(wallet.wallet).values),
            message: message,
          ),
        );

  @override
  State<RunnerCelebration> createState() => _RunnerCelebrationState();
}

class _RunnerCelebrationState extends State<RunnerCelebration>
    with SingleTickerProviderStateMixin {
  // 한 번에 두 번 뛰고, 세 번 반복한 뒤 만세 자세로 멈춥니다.
  late final _play = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _play.value = 1;
    } else {
      _play.repeat(count: 3);
    }
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      container: true,
      label: '내 러너가 ${widget.message}라고 축하해요',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: TrackBackgroundPainter(dark: dark)),
                AnimatedBuilder(
                  animation: _play,
                  builder: (context, _) {
                    final pose = celebrationPose(
                      _play.isAnimating ? _play.value : 1,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: ConfettiPainter(
                            progress: _play.isAnimating
                                ? (_play.lastElapsedDuration?.inMilliseconds ??
                                          0) /
                                      1800
                                : 0,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 34),
                          child: CustomPaint(
                            key: const ValueKey('celebrating-runner'),
                            painter: RunnerCharacterPainter(
                              yaw: pose.yaw,
                              outfit: widget.outfit,
                              cheer: pose.cheer,
                              hop: pose.hop,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 10,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(color: Color(0x22000000), blurRadius: 8),
                        ],
                      ),
                      child: Text(
                        widget.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF191F28),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 축하 동작 한 장면입니다. [t]는 한 번(두 번 깡충) 동작의 0~1 진행도입니다.
({double hop, double cheer, double yaw}) celebrationPose(double t) {
  // 0~0.8: 두 번 깡충(만세), 0.8~1: 착지한 채 만세 유지.
  final jumping = t < 0.8;
  final phase = (t / 0.4) % 1;
  final hop = jumping ? math.sin(phase * math.pi) * 0.18 : 0.0;
  // 뛰어오를 때 팔이 번쩍, 착지 순간엔 살짝 내려옵니다.
  final cheer = jumping ? 0.75 + 0.25 * math.sin(phase * math.pi) : 1.0;
  final yaw = -0.3 + math.sin(t * math.pi * 2) * 0.18;
  return (hop: hop, cheer: cheer, yaw: yaw);
}

/// 위에서 떨어지는 알록달록한 색종이입니다.
class ConfettiPainter extends CustomPainter {
  ConfettiPainter({required this.progress});

  /// 0이면 색종이가 없고, 커질수록 아래로 떨어집니다(반복마다 다시 위에서).
  final double progress;

  static const _colors = [
    Color(0xFF3182F6),
    Color(0xFFFF7A1A),
    Color(0xFFFFC83D),
    Color(0xFF2BC48A),
    Color(0xFFF65A8E),
    Color(0xFF8B5CF6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final random = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < 26; i++) {
      final x = random.nextDouble() * size.width;
      final speed = 0.6 + random.nextDouble() * 0.6;
      final start = random.nextDouble();
      final y = ((start + progress * speed) % 1.0) * (size.height + 20) - 10;
      final spin = progress * (4 + random.nextDouble() * 6) + i;
      final w = 5 + random.nextDouble() * 4;
      paint.color = _colors[i % _colors.length];
      canvas
        ..save()
        ..translate(x + math.sin(spin) * 8, y)
        ..rotate(spin);
      if (i.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.55),
            const Radius.circular(1.5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, w * 0.35, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.progress != progress;
}

/// 레벨이 오르면 만세하는 작은 캐릭터 주위로 별이 반짝입니다.
class LevelUpRunner extends StatefulWidget {
  const LevelUpRunner({
    this.outfit = CharacterOutfit.none,
    this.size = 64,
    super.key,
  });

  final CharacterOutfit outfit;
  final double size;

  @override
  State<LevelUpRunner> createState() => _LevelUpRunnerState();
}

class _LevelUpRunnerState extends State<LevelUpRunner>
    with SingleTickerProviderStateMixin {
  late final _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) _glow.repeat(count: 4);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _glow,
        builder: (context, _) {
          final t = _glow.value;
          final hop = _glow.isAnimating ? math.sin(t * math.pi) * 0.12 : 0.0;
          return CustomPaint(
            painter: _SparklePainter(_glow.isAnimating ? t : 0.35),
            child: CustomPaint(
              key: const ValueKey('level-up-runner'),
              painter: RunnerCharacterPainter(
                yaw: -0.3,
                outfit: widget.outfit,
                cheer: 1,
                hop: hop,
                ground: false,
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// 캐릭터 둘레에서 커졌다 작아지는 네 갈래 별입니다.
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const spots = [
      (0.12, 0.2, 0.0),
      (0.86, 0.14, 0.33),
      (0.92, 0.62, 0.66),
      (0.06, 0.66, 0.5),
    ];
    final paint = Paint()..color = const Color(0xFFFFE066);
    for (final (x, y, delay) in spots) {
      final k = math.sin(((t + delay) % 1) * math.pi);
      final r = size.shortestSide * 0.09 * k;
      if (r < 0.5) continue;
      final c = Offset(size.width * x, size.height * y);
      final star = Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
        ..close();
      canvas.drawPath(star, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}
