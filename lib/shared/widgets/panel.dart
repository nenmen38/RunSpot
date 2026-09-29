import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
