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
}
