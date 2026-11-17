import 'package:flutter/material.dart';

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

/// 눌러서 들어가는 화면(첫 화면 제외)을 넓은 화면에서 읽기 좋은 폭으로 가운데에 둡니다.
/// 원래 화면 전환 효과는 그대로 쓰고, 폭만 감쌉니다. 일반 폰에서는 아무것도 바뀌지 않습니다.
class ReadableWidthTransitionsBuilder extends PageTransitionsBuilder {
  const ReadableWidthTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      inner.delegatedTransition;

  @override
  Duration get transitionDuration => inner.transitionDuration;

  @override
  Duration get reverseTransitionDuration => inner.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    route.isFirst ? child : ReadablePage(child: child),
  );

  /// 기본 화면 전환 효과마다 폭 제한을 씌운 설정입니다.
  static PageTransitionsTheme theme() => PageTransitionsTheme(
    builders: {
      for (final entry in const PageTransitionsTheme().builders.entries)
        entry.key: ReadableWidthTransitionsBuilder(entry.value),
    },
  );
}

/// 폭이 [maxWidth]보다 넓으면 가운데에 [maxWidth]만큼만 쓰고 양옆은 바탕색으로 채웁니다.
class ReadablePage extends StatelessWidget {
  const ReadablePage({required this.child, this.maxWidth = 720, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth <= maxWidth) return child;
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: SizedBox(width: maxWidth, child: child),
        ),
      );
    },
  );
}
