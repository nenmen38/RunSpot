import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';

/// 기록 화면의 수치와 경고는 밝은 배경에서 충분한 대비를 유지합니다.
class RunRecordColors {
  static Color get label =>
      AppColors.dark ? const Color(0xFFB4BFCC) : const Color(0xFF475569);
  static Color get warning =>
      AppColors.dark ? const Color(0xFFFFB168) : const Color(0xFF9A4D00);
  static Color get danger =>
      AppColors.dark ? const Color(0xFFFF8A80) : const Color(0xFFB42318);
  static Color get tableHeading =>
      AppColors.dark ? const Color(0xFF1C2B42) : const Color(0xFFEFF6FF);
}

ThemeData runRecordTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surface,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: AppColors.line,
  );
}
