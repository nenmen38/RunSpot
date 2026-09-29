import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/panel.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Panel(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: constraints.hasBoundedHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.blue, size: 19),
            if (constraints.hasBoundedHeight)
              const Spacer()
            else
              const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
