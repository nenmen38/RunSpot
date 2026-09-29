import 'package:flutter/material.dart';

class Achievement {
  const Achievement(this.title, this.value, this.icon, this.progress);

  final String title;
  final String value;
  final IconData icon;
  final double progress;
}
