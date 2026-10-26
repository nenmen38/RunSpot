import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';

/// 기록 화면의 수치와 경고는 밝은 배경에서 충분한 대비를 유지합니다.
class RunRecordColors {
  static const label = Color(0xFF475569);
  static const warning = Color(0xFF9A4D00);
  static const danger = Color(0xFFB42318);
  static const tableHeading = Color(0xFFEFF6FF);
}

ThemeData runRecordTheme(BuildContext context) {
  final base = Theme.of(context);
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
    ),
    dividerColor: AppColors.line,
  );
}
