import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class MetricValue extends StatelessWidget {
  const MetricValue({required this.label, required this.value, super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
      ),
      const SizedBox(height: 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}
