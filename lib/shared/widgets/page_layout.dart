import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: ValueKey(child.runtimeType), child: child);
  }
}

class AppTopBar extends StatelessWidget {
  const AppTopBar({required this.title, required this.subtitle, super.key});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.directions_run,
            color: Colors.white,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none),
          color: AppColors.blue,
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.blueSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.blue, size: 19),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
