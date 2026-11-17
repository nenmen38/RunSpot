import 'package:flutter/material.dart';
import 'package:runquest/app/mobile_app_viewport.dart';
import 'package:runquest/app/run_quest_shell.dart';
import 'package:runquest/features/auth/auth_gate.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';
import 'package:runquest/shared/layout/readable_width.dart';
import 'package:runquest/shared/theme/app_colors.dart';

/// 라이트·다크 테마를 만듭니다. 공통 색(AppColors)을 해당 밝기로 잠시 바꿔 계산합니다.
ThemeData buildAppTheme({required bool dark}) {
  final previous = AppColors.dark;
  AppColors.dark = dark;
  try {
    final brightness = dark ? Brightness.dark : Brightness.light;
    final ink = AppColors.ink;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: brightness,
        primary: AppColors.blue,
        surface: AppColors.surface,
        onSurface: ink,
        secondary: AppColors.blueDark,
        secondaryContainer: AppColors.blueSoft,
        onSecondaryContainer: dark
            ? const Color(0xFFB9D4FF)
            : AppColors.blueDark,
        outlineVariant: AppColors.line,
        surfaceTint: Colors.transparent,
      ),
      dividerColor: AppColors.line,
      // 폴드를 펼친 화면에서도 눌러서 들어간 화면이 읽기 좋은 폭을 넘지 않게 합니다.
      pageTransitionsTheme: ReadableWidthTransitionsBuilder.theme(),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          height: 1.14,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
        bodyMedium: TextStyle(
          color: ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        labelLarge: TextStyle(
          color: ink,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  } finally {
    AppColors.dark = previous;
  }
}

class RunQuestApp extends StatelessWidget {
  const RunQuestApp({super.key, this.appearance});

  /// 테스트에서 바꿔 끼울 수 있게 합니다. 없으면 앱 공용 설정을 씁니다.
  final AppAppearance? appearance;

  static final _light = buildAppTheme(dark: false);
  static final _dark = buildAppTheme(dark: true);

  @override
  Widget build(BuildContext context) {
    final settings = appearance ?? AppAppearance.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RunSpot',
        theme: _light,
        darkTheme: _dark,
        themeMode: settings.theme.mode,
        // 색을 한 번에 바꿔 일부만 늦게 바뀌어 보이지 않게 합니다.
        themeAnimationDuration: Duration.zero,
        builder: (context, child) =>
            AppearanceScope(textScale: settings.textSize.scale, child: child!),
        home: const MobileAppViewport(child: AuthGate(child: RunQuestShell())),
      ),
    );
  }
}

/// 현재 테마 밝기를 공통 색에 반영하고, 고른 글자 크기를 기기 설정에 곱해 적용합니다.
/// 밝기가 바뀌면 화면 전체를 다시 그려 직접 지정한 색도 함께 바뀌게 합니다.
class AppearanceScope extends StatefulWidget {
  const AppearanceScope({
    required this.textScale,
    required this.child,
    super.key,
  });

  final double textScale;
  final Widget child;

  @override
  State<AppearanceScope> createState() => _AppearanceScopeState();
}

class _AppearanceScopeState extends State<AppearanceScope> {
  bool? _dark;

  void _rebuildAll() {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    if (mounted) (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    AppColors.dark = dark;
    if (_dark != null && _dark != dark) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    _dark = dark;
    final media = MediaQuery.of(context);
    final system = media.textScaler.scale(14) / 14;
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(system * widget.textScale),
      ),
      child: widget.child,
    );
  }
}
