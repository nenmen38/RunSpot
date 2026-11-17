import 'package:flutter/material.dart';

import '../widgets/board_theme.dart';

/// 기존 대회 화면에서도 게시판 공통 색상을 사용합니다.
abstract final class MarathonStyle {
  static Color get secondary => BoardStyle.secondary;
}
