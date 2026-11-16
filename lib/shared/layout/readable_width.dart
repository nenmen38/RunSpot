import 'package:flutter/widgets.dart';

/// 폴드를 펼친 화면이나 태블릿처럼 넓은 화면에서 내용이 끝까지 늘어나지 않게 폭을 제한합니다.
/// 일반 폰에서는 화면 폭이 [maxWidth]보다 좁아 아무것도 바뀌지 않습니다.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({required this.child, this.maxWidth = 640, super.key});

  static const wideBreakpoint = 600.0;

  /// 왼쪽 세로 메뉴를 쓰는 넓은 화면인지 여부입니다. 앱이 실제로 받은 폭으로 판단합니다.
  static bool isWide(BoxConstraints constraints) =>
      constraints.maxWidth >= wideBreakpoint;

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
