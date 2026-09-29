import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class BadgePill extends StatelessWidget {
  const BadgePill({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.blueDark,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
