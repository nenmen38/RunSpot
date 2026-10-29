import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import 'marathon_event.dart';
import 'marathon_style.dart';

class MarathonStatusBadge extends StatelessWidget {
  const MarathonStatusBadge({required this.status, super.key});
  final MarathonStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: status == MarathonStatus.open
          ? AppColors.blueSoft
          : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      status.label,
      style: TextStyle(
        color: status == MarathonStatus.open
            ? AppColors.blueDark
            : MarathonStyle.secondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    ),
  );
}
