import 'package:flutter/material.dart';

class Achievement {
  const Achievement(
    this.title,
    this.value,
    this.icon,
    this.progress, {
    this.achievedAt,
  });
  final DateTime? achievedAt;

  final String title;
  final String value;
  final IconData icon;
  final double progress;
  factory Achievement.fromJson(dynamic row) {
    final progress = row['progress'] as int;
    final target = row['target'] as int;
    if (target <= 0 || progress < 0 || progress > target) {
      throw const FormatException('업적 응답을 확인해 주세요.');
    }
    final distance = row['metric'] == 'distance_m';
    return Achievement(
      row['title'] as String,
      distance
          ? '${(progress / 1000).toStringAsFixed(1)} / ${target ~/ 1000}km'
          : '$progress / $target회',
      Icons.military_tech_outlined,
      progress / target,
      achievedAt: row['achieved_at'] == null
          ? null
          : DateTime.parse(row['achieved_at'] as String),
    );
  }
}
