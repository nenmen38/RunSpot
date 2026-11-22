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
    // 버튼·입력창·카드·창의 모서리를 한 기준으로 맞춥니다.
    const radius = 14.0;
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    // 테두리선은 너무 진하지 않게 부드러운 회색을 씁니다.
    final outline = dark ? const Color(0xFF4A515B) : const Color(0xFFD1D6DB);
    final buttonText = const TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      letterSpacing: -.1,
    );
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
        outline: outline,
        outlineVariant: AppColors.line,
        surfaceTint: Colors.transparent,
      ),
      dividerColor: AppColors.line,
      dividerTheme: DividerThemeData(color: AppColors.line),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: rounded,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: rounded,
          side: BorderSide(color: outline),
          foregroundColor: ink,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: rounded,
          foregroundColor: AppColors.blueText,
          textStyle: buttonText.copyWith(fontSize: 14),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: rounded,
          side: BorderSide(color: outline),
          selectedBackgroundColor: AppColors.blueSoft,
          selectedForegroundColor: AppColors.blueText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        // 테두리 모양만 정하고 색은 상태(기본·선택·오류)에 맞춰 자동으로 바뀝니다.
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(
          color: AppColors.gray,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        dragHandleColor: outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        shape: rounded,
        elevation: 3,
      ),
      // 알림 문구는 화면 아래에 떠 있는 둥근 상자로 보여줍니다.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF2C3139)
            : const Color(0xFF333D4B),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: const Color(0xFF7DB2FF),
        shape: rounded,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: AppColors.line),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.blue,
        linearTrackColor: AppColors.blueSoft,
        circularTrackColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? AppColors.blueText
                : AppColors.gray,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.blueText
                : AppColors.gray,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: AppColors.line,
        labelColor: AppColors.blueText,
        unselectedLabelColor: AppColors.gray,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      // 폴드를 펼친 화면에서도 눌러서 들어간 화면이 읽기 좋은 폭을 넘지 않게 합니다.
      pageTransitionsTheme: ReadableWidthTransitionsBuilder.theme(),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: .5,
        shadowColor: AppColors.line,
        titleTextStyle: TextStyle(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
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
        title: '뜀터',
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
