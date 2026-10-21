import 'package:flutter/material.dart';
import 'package:runquest/features/profile/models/achievement.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class AchievementRow extends StatelessWidget {
  const AchievementRow({required this.achievement, super.key});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(achievement.icon, color: AppColors.blue, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      achievement.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    achievement.value,
                    style: const TextStyle(
                      color: AppColors.gray,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              if (achievement.achievedAt case final date?)
                Text(
                  '달성 ${date.toLocal().year}.${date.toLocal().month}.${date.toLocal().day}',
                ),
              LinearProgressIndicator(
                value: achievement.progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(99),
                color: AppColors.blue,
                backgroundColor: AppColors.line,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
