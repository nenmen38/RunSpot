import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 내용을 불러오는 동안 실제 화면 모양을 흐린 회색 뼈대로 먼저 보여주고, 빛이 지나가듯 반짝입니다.
/// 안의 [SkeletonBox]들이 한 번에 같은 빛을 받도록 이 위젯 하나로 감쌉니다.
class Shimmer extends StatefulWidget {
  const Shimmer({required this.child, super.key});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 동작 줄이기 설정이면 반짝임 없이 회색 뼈대만 보여줍니다.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.dark
        ? const Color(0xFF262A30)
        : const Color(0xFFE4E8EC);
    final light = AppColors.dark
        ? const Color(0xFF343941)
        : const Color(0xFFF8F9FA);
    return Semantics(
      label: '불러오는 중',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          child: widget.child,
          builder: (context, child) => ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) {
              final x = _controller.value * 3 - 1;
              return LinearGradient(
                begin: Alignment(x - 1, -.3),
                end: Alignment(x + 1, .3),
                colors: [base, light, base],
                stops: const [.35, .5, .65],
              ).createShader(bounds);
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 뼈대의 한 조각(글줄·사진·동그라미)입니다. 반드시 [Shimmer] 안에 둡니다.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({this.width, this.height = 12, this.radius = 6, super.key})
    : circle = false;

  const SkeletonBox.circle({required double size, super.key})
    : width = size,
      height = size,
      radius = 0,
      circle = true;

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      // 색은 [Shimmer]가 덮어 그리므로 아무 불투명한 색이면 됩니다.
      color: Colors.black,
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

/// 자주 쓰는 목록 모양의 뼈대입니다.
enum SkeletonLayout {
  /// 동그란 사진·두 줄 글(대화 목록·알림·친구)
  rows,

  /// 제목·본문·아래 정보가 있는 카드(게시판)
  cards,

  /// 양쪽으로 오가는 말풍선(대화방)
  chat,
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({
    this.layout = SkeletonLayout.rows,
    this.count = 6,
    super.key,
  });

  final SkeletonLayout layout;
  final int count;

  @override
  Widget build(BuildContext context) => Shimmer(
    // 넓은 자리에서도, 다른 목록 안에서도 쓸 수 있게 내용 높이만큼만 차지합니다.
    child: ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: count,
      itemBuilder: (context, index) => switch (layout) {
        SkeletonLayout.rows => _row(index),
        SkeletonLayout.cards => _card(index),
        SkeletonLayout.chat => _bubble(index),
      },
    ),
  );

  // 줄 길이를 조금씩 달리해 실제 글처럼 보이게 합니다.
  static const _widths = [.62, .48, .7, .55, .4, .66];

  Widget _row(int index) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        const SkeletonBox.circle(size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: box.maxWidth * .38, height: 13),
                const SizedBox(height: 8),
                SkeletonBox(
                  width: box.maxWidth * _widths[index % _widths.length],
                  height: 11,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _card(int index) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 52, height: 18, radius: 9),
              const SizedBox(height: 12),
              SkeletonBox(
                width: box.maxWidth * _widths[index % _widths.length],
                height: 15,
              ),
              const SizedBox(height: 10),
              SkeletonBox(width: box.maxWidth, height: 11),
              const SizedBox(height: 6),
              SkeletonBox(width: box.maxWidth * .8, height: 11),
              const SizedBox(height: 14),
              const Row(
                children: [
                  SkeletonBox.circle(size: 20),
                  SizedBox(width: 8),
                  SkeletonBox(width: 60, height: 10),
                  Spacer(),
                  SkeletonBox(width: 70, height: 10),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _bubble(int index) {
    final mine = index.isOdd;
    final width = 90.0 + 40 * (index % 3);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!mine) ...[
            const SkeletonBox.circle(size: 32),
            const SizedBox(width: 8),
          ],
          SkeletonBox(width: width, height: 38, radius: 18),
        ],
      ),
    );
  }
}
