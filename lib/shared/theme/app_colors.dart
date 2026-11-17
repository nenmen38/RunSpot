import 'package:flutter/material.dart';

/// 앱 공통 색입니다. 배경·글자·선처럼 밝기에 따라 달라지는 색은 [dark]에 맞춰 바뀝니다.
/// [dark]는 앱 최상단(RunQuestApp)에서 현재 테마 밝기로 정합니다.
class AppColors {
  /// 지금 다크 모드로 그리는 중인지 여부입니다.
  static bool dark = false;

  static const blue = Color(0xFF3182F6);
  static const blueDark = Color(0xFF1B64DA);
  static Color get blueSoft =>
      dark ? const Color(0xFF1C2B42) : const Color(0xFFE8F3FF);

  /// 화면 바탕색입니다.
  static Color get bg =>
      dark ? const Color(0xFF101215) : const Color(0xFFF7F8FA);

  /// 카드·패널·입력창처럼 바탕 위에 올라가는 면의 색입니다. (라이트 모드의 흰색)
  static Color get surface => dark ? const Color(0xFF1B1E23) : Colors.white;

  /// 기본 글자색입니다.
  static Color get ink =>
      dark ? const Color(0xFFE8EAED) : const Color(0xFF191F28);
  static Color get gray =>
      dark ? const Color(0xFF9AA4B0) : const Color(0xFF6B7684);
  static Color get line =>
      dark ? const Color(0xFF30353C) : const Color(0xFFE5E8EB);
  static const green = Color(0xFF00B894);
  static const orange = Color(0xFFFF9F1C);
  static const red = Color(0xFFE34949);
  static const purple = Color(0xFF7C5CFF);

  /// 채팅에서 상대가 아직 읽지 않은 메시지의 '1' 색입니다. 밝은 배경에서도 보이게 진한 노랑을 씁니다.
  static const unreadMark = Color(0xFFE5A800);
}
