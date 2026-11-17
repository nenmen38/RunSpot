import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

/// 게시판 안에서만 사용하는 색·글자 위계입니다. 다른 탭의 테마는 바꾸지 않습니다.
abstract final class BoardStyle {
  static bool get _dark => AppColors.dark;
  static Color get ink => AppColors.ink;
  static Color get secondary =>
      _dark ? const Color(0xFFA5AFBB) : const Color(0xFF596574);
  static Color get accent =>
      _dark ? const Color(0xFF6AA6FF) : const Color(0xFF1B64DA);
  static Color get accentSoft => AppColors.blueSoft;
  static Color get surface =>
      _dark ? const Color(0xFF23272D) : const Color(0xFFF5F6F8);
  static Color get line => AppColors.line;
  static const error = Color(0xFFBC3344);
  static TextStyle get title => TextStyle(
    color: ink,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );
  static TextStyle get section => TextStyle(
    color: ink,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static TextStyle get body => TextStyle(
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.65,
  );
  static TextStyle get meta => TextStyle(
    color: secondary,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
}

class BoardTheme extends StatelessWidget {
  const BoardTheme({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: BoardStyle.line),
    );
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: AppColors.surface,
        colorScheme: base.colorScheme.copyWith(
          primary: BoardStyle.accent,
          onPrimary: Colors.white,
          secondary: BoardStyle.accent,
          secondaryContainer: BoardStyle.accentSoft,
          onSecondaryContainer: BoardStyle.accent,
          surface: AppColors.surface,
          surfaceTint: Colors.transparent,
          error: BoardStyle.error,
        ),
        textTheme: base.textTheme.copyWith(
          headlineSmall: BoardStyle.title,
          titleLarge: BoardStyle.title,
          titleMedium: BoardStyle.section,
          bodyLarge: BoardStyle.body,
          bodyMedium: BoardStyle.body,
          bodySmall: BoardStyle.meta,
          labelLarge: TextStyle(
            color: BoardStyle.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: BoardStyle.meta,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: BoardStyle.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: BoardStyle.ink,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        dividerTheme: DividerThemeData(
          color: BoardStyle.line,
          thickness: .5,
          space: 1,
        ),
        iconTheme: IconThemeData(color: BoardStyle.secondary, size: 22),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: BoardStyle.accent,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: rounded,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: BoardStyle.ink,
            minimumSize: const Size(48, 48),
            side: BorderSide(color: BoardStyle.line),
            shape: rounded,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: BoardStyle.accent,
            minimumSize: const Size(48, 48),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        chipTheme: base.chipTheme.copyWith(
          backgroundColor: BoardStyle.surface,
          selectedColor: BoardStyle.accentSoft,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          showCheckmark: false,
          labelStyle: TextStyle(
            color: BoardStyle.ink,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
            side: const WidgetStatePropertyAll(BorderSide.none),
            shape: WidgetStatePropertyAll(rounded),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? BoardStyle.accentSoft
                  : BoardStyle.surface,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? BoardStyle.accent
                  : BoardStyle.secondary,
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: BoardStyle.surface,
          border: border,
          enabledBorder: border.copyWith(borderSide: BorderSide.none),
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: BoardStyle.accent, width: 1.5),
          ),
          errorBorder: border.copyWith(
            borderSide: const BorderSide(color: BoardStyle.error),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          hintStyle: TextStyle(
            color: BoardStyle.secondary,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          labelStyle: TextStyle(color: BoardStyle.secondary, fontSize: 14),
          counterStyle: BoardStyle.meta,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: TextStyle(
            color: BoardStyle.ink,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          contentTextStyle: BoardStyle.body,
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: rounded,
          textStyle: BoardStyle.body,
        ),
      ),
      child: child,
    );
  }
}

class BoardLabel extends StatelessWidget {
  const BoardLabel({required this.text, this.emphasized = false, super.key});
  final String text;
  final bool emphasized;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: emphasized ? BoardStyle.accentSoft : BoardStyle.surface,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: emphasized ? BoardStyle.accent : BoardStyle.secondary,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
    ),
  );
}
