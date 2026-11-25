import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_colors.dart';
import '../settings/appearance/app_appearance.dart';

/// 앱을 처음 켠 사람에게 하단 메뉴를 하나씩 직접 눌러 보게 하는 둘러보기입니다.
/// 끝내거나 건너뛰면 이 기기에 기억해 다시 띄우지 않고, 설정에서 다시 볼 수 있습니다.
class AppTour extends ChangeNotifier {
  AppTour({AppearanceStore? store}) : _given = store;

  static final instance = AppTour();
  static const _key = 'onboarding.tour.v1';

  final AppearanceStore? _given;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();

  bool _loaded = false;
  bool _done = true;

  /// 지금 둘러보기를 띄워야 하는지입니다(불러오기 전에는 띄우지 않습니다).
  bool get showing => _loaded && !_done;

  Future<void> load() async {
    try {
      _done = await _store.read(_key) == 'done';
    } catch (_) {
      // 기록을 읽지 못하면 처음 실행으로 보지 않고 띄우지 않습니다.
      _done = true;
    }
    _loaded = true;
    notifyListeners();
  }

  /// 끝까지 보거나 건너뛰면 다시 띄우지 않습니다.
  Future<void> finish() async {
    _done = true;
    notifyListeners();
    try {
      await _store.write(_key, 'done');
    } catch (_) {}
  }

  /// 설정에서 '앱 둘러보기'를 누르면 처음부터 다시 보여줍니다.
  void restart() {
    _loaded = true;
    _done = false;
    notifyListeners();
  }
}

/// 둘러보기의 한 단계입니다. [tab]이 있으면 그 하단 메뉴를 직접 눌러 보게 합니다.
class AppTourStep {
  const AppTourStep({
    required this.title,
    required this.body,
    this.tab,
    this.icon = Icons.waving_hand_outlined,
    this.after,
  });

  final int? tab;
  final String title;

  /// 메뉴를 누르기 전 안내입니다.
  final String body;

  /// 메뉴를 누른 뒤 그 화면을 보며 읽는 설명입니다.
  final String? after;
  final IconData icon;
}

const appTourSteps = [
  AppTourStep(
    title: '뜀터에 오신 걸 환영해요',
    body: '아래 메뉴를 직접 눌러 보며 주요 기능을 30초 만에 둘러봐요.',
  ),
  AppTourStep(
    tab: 0,
    icon: Icons.map,
    title: '홈 · 러닝 지도',
    body: "아래 '홈'을 눌러 보세요.",
    after:
        "지도에서 내 위치와 주변 러너를 보고, 아래 '러닝 시작'을 누르면 바로 기록이 시작돼요. "
        '날씨·미세먼지 같은 러닝 환경도 여기서 확인해요.',
  ),
  AppTourStep(
    tab: 1,
    icon: Icons.groups,
    title: '소셜 · 친구와 크루',
    body: "이번엔 '소셜'을 눌러 보세요.",
    after: '닉네임으로 친구를 찾고, 크루에 들어가고, 대화하며 함께 달리기에 초대할 수 있어요.',
  ),
  AppTourStep(
    tab: 2,
    icon: Icons.person,
    title: '프로필 · 내 기록',
    body: "'프로필'을 눌러 보세요.",
    after: '레벨과 주간 목표, 지난 러닝 기록과 통계, 모은 칭호를 한곳에서 봐요.',
  ),
  AppTourStep(
    tab: 3,
    icon: Icons.forum,
    title: '게시판 · 러닝 소식',
    body: "'게시판'을 눌러 보세요.",
    after: '우리 동네 러닝 이야기와 코스·맛집 추천, 러닝 대회 일정을 나눠요.',
  ),
  AppTourStep(
    tab: 4,
    icon: Icons.inventory_2,
    title: '아이템 · 꾸미기',
    body: "마지막으로 '아이템'을 눌러 보세요.",
    after: '달리며 모은 코인으로 지도 테두리·경로 색·말풍선 같은 꾸미기 아이템을 받아요.',
  ),
  AppTourStep(
    icon: Icons.directions_run,
    title: '이제 달려 볼까요?',
    body: "홈의 '러닝 시작'을 누르면 바로 첫 러닝이 시작돼요. 설정에서 언제든 둘러보기를 다시 볼 수 있어요.",
  ),
];

/// 화면 전체를 덮는 둘러보기입니다. 눌러 볼 메뉴만 밝게 뚫어 보여주고, 그 자리를 누르면
/// 실제로 그 탭으로 옮겨 간 뒤 설명을 보여줍니다.
class AppTourOverlay extends StatefulWidget {
  const AppTourOverlay({
    required this.targetOf,
    required this.onSelectTab,
    required this.onDone,
    this.steps = appTourSteps,
    super.key,
  });

  /// 하단(또는 왼쪽) 메뉴 [tab]의 화면 위치입니다. 아직 그려지지 않았으면 null입니다.
  final Rect? Function(int tab) targetOf;
  final ValueChanged<int> onSelectTab;

  /// 끝까지 보거나 건너뛰면 불립니다.
  final VoidCallback onDone;
  final List<AppTourStep> steps;

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay>
    with SingleTickerProviderStateMixin {
  int _step = 0;

  /// 메뉴를 눌러서 그 화면 설명을 보는 중인지입니다.
  bool _explaining = false;
  Rect? _target;

  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  AppTourStep get _current => widget.steps[_step];

  @override
  void initState() {
    super.initState();
    _measureSoon();
  }

  /// 눌러 볼 메뉴를 비출 때만 고리를 퍼뜨립니다(동작 줄이기 설정이면 멈춥니다).
  void _syncPulse(bool spotlight) {
    final animate = spotlight && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!animate && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // 메뉴 위치는 화면이 그려진 뒤에 알 수 있어 다음 장면에서 잽니다(화면을 돌려도 다시 잽니다).
  void _measureSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tab = _current.tab;
      final global = tab == null || _explaining ? null : widget.targetOf(tab);
      final box = context.findRenderObject() as RenderBox?;
      // 메뉴의 화면 위치를 이 덮개 기준 위치로 바꿉니다.
      final rect = global == null || box == null || !box.hasSize
          ? null
          : global.shift(box.globalToLocal(Offset.zero));
      if (rect != _target) setState(() => _target = rect);
    });
  }

  void _next() {
    unawaited(HapticFeedback.selectionClick());
    if (_step == widget.steps.length - 1) {
      widget.onSelectTab(0);
      widget.onDone();
      return;
    }
    setState(() {
      _step++;
      _explaining = false;
      _target = null;
    });
    _measureSoon();
  }

  /// 밝게 뚫린 메뉴를 누르면 진짜로 그 탭으로 옮겨 가고 설명을 보여줍니다.
  void _tapTarget() {
    final tab = _current.tab;
    if (tab == null) return;
    unawaited(HapticFeedback.selectionClick());
    widget.onSelectTab(tab);
    setState(() {
      _explaining = true;
      _target = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // 화면 전체가 아니라 이 덮개가 실제로 차지한 크기를 기준으로 배치합니다.
    builder: (context, constraints) => _build(context, constraints.biggest),
  );

  Widget _build(BuildContext context, Size size) {
    final step = _current;
    final pointing = step.tab != null && !_explaining;
    final target = pointing ? _target : null;
    if (pointing && target == null) _measureSoon();
    final padding = MediaQuery.paddingOf(context);
    final hole = target?.inflate(6);
    _syncPulse(hole != null);
    // 메뉴가 화면 아래에 있으면 설명 상자를 그 위에, 왼쪽에 있으면(넓은 화면) 오른쪽에 둡니다.
    final cardWidth = math.min(360.0, size.width - 32);
    Widget card = _TourCard(
      step: step,
      index: _step,
      count: widget.steps.length,
      explaining: _explaining,
      onNext: _next,
      onSkip: widget.onDone,
    );
    final Widget placed;
    if (hole != null && hole.center.dy > size.height / 2) {
      placed = Positioned(
        left: (hole.center.dx - cardWidth / 2).clamp(
          16.0,
          size.width - cardWidth - 16,
        ),
        bottom: size.height - hole.top + 18,
        width: cardWidth,
        child: card,
      );
    } else if (hole != null) {
      placed = Positioned(
        left: hole.right + 18,
        top: (hole.center.dy - 90).clamp(padding.top + 16, size.height - 260),
        width: math.min(cardWidth, size.width - hole.right - 34),
        child: card,
      );
    } else {
      placed = Positioned(
        left: (size.width - cardWidth) / 2,
        bottom: padding.bottom + 96,
        width: cardWidth,
        child: card,
      );
    }
    return Stack(
      children: [
        // 화면을 어둡게 덮고(설명 중엔 옅게) 눌러 볼 메뉴만 뚫어 둡니다. 다른 곳은 눌리지 않습니다.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => CustomPaint(
                painter: _SpotlightPainter(
                  hole: hole,
                  pulse: _pulse.value,
                  dim: _explaining ? 0.38 : 0.66,
                ),
              ),
            ),
          ),
        ),
        if (hole != null)
          Positioned.fromRect(
            rect: hole,
            child: Semantics(
              button: true,
              label: '${step.title} 메뉴 누르기',
              child: GestureDetector(
                key: const ValueKey('tour-target'),
                behavior: HitTestBehavior.opaque,
                onTap: _tapTarget,
              ),
            ),
          ),
        if (hole != null)
          _PointingHand(hole: hole, animation: _pulse, height: size.height),
        placed,
        if (_step < widget.steps.length - 1)
          Positioned(
            top: padding.top + 10,
            right: 12,
            child: TextButton(
              key: const ValueKey('tour-skip'),
              onPressed: widget.onDone,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('건너뛰기'),
            ),
          ),
      ],
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.index,
    required this.count,
    required this.explaining,
    required this.onNext,
    required this.onSkip,
  });

  final AppTourStep step;
  final int index;
  final int count;
  final bool explaining;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final first = index == 0;
    final last = index == count - 1;
    final pointing = step.tab != null && !explaining;
    return Material(
      color: AppColors.surface,
      elevation: 8,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.blueSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(step.icon, size: 18, color: AppColors.blueText),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(step.title, style: text.titleMedium)),
                // 진행 점: 지금 단계를 파란 막대로 보여줍니다.
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(left: 3),
                        width: i == index ? 14 : 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: i <= index ? AppColors.blue : AppColors.line,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              explaining ? (step.after ?? step.body) : step.body,
              style: text.bodyMedium?.copyWith(height: 1.45),
            ),
            if (!pointing) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (first)
                    TextButton(onPressed: onSkip, child: const Text('다음에 볼게요')),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('tour-next'),
                    onPressed: onNext,
                    child: Text(
                      first
                          ? '둘러보기 시작'
                          : last
                          ? '시작하기'
                          : '다음',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 어두운 막에 둥근 구멍을 뚫고, 구멍 둘레에 퍼지는 고리로 눌러 볼 곳을 알려줍니다.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({
    required this.hole,
    required this.pulse,
    required this.dim,
  });

  final Rect? hole;
  final double pulse;
  final double dim;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final hole = this.hole;
    final scrim = Paint()..color = Colors.black.withValues(alpha: dim);
    if (hole == null) {
      canvas.drawPath(screen, scrim);
      return;
    }
    final shape = RRect.fromRectAndRadius(hole, const Radius.circular(18));
    canvas.drawPath(
      Path.combine(PathOperation.difference, screen, Path()..addRRect(shape)),
      scrim,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
    final grow = 10 * pulse;
    canvas.drawRRect(
      shape.inflate(grow),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.6 * (1 - pulse)),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.hole != hole || old.pulse != pulse || old.dim != dim;
}

/// 눌러 볼 메뉴를 콕콕 가리키는 손가락입니다.
class _PointingHand extends StatelessWidget {
  const _PointingHand({
    required this.hole,
    required this.animation,
    required this.height,
  });

  final Rect hole;
  final double height;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final below = hole.center.dy < height / 2;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final tap = math.sin(animation.value * math.pi * 2).abs() * 6;
        // 메뉴 이름을 가리지 않게 구멍 오른쪽 아래 모서리에서 콕콕 누르는 손가락을 둡니다.
        return Positioned(
          left: hole.right - 20,
          top: (below ? hole.bottom - 10 : hole.center.dy - 4) + tap,
          child: const IgnorePointer(
            child: Icon(Icons.touch_app, color: Colors.white, size: 32),
          ),
        );
      },
    );
  }
}
