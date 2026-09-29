import 'package:flutter/material.dart';
import 'package:runquest/features/course/models/run_preset.dart';
import 'package:runquest/shared/theme/app_colors.dart';

const presets = [
  RunPreset('야간 안전런', '안전 우선', Icons.shield_outlined, AppColors.blue),
  RunPreset('페이스런', '신호 적게', Icons.speed_outlined, AppColors.orange),
  RunPreset('업힐런', '경사 도전', Icons.terrain_outlined, AppColors.red),
  RunPreset('힐링런', '공원/하천', Icons.park_outlined, AppColors.green),
  RunPreset('10K 기록 도전', '정확한 10K', Icons.flag_outlined, AppColors.purple),
];
