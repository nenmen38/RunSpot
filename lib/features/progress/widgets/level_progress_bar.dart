import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../models/run_progress.dart';

class LevelProgressBar extends StatelessWidget {
  const LevelProgressBar({required this.progress, this.from, super.key});
  final RunProgress progress;

  /// 지정하면 이 비율에서 현재 진행도까지 채워지는 애니메이션을 보여 줍니다.
  final double? from;

  @override
  Widget build(BuildContext context) {
    final caption = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Lv.${progress.level}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Flexible(
              child: Text(
                progress.isMaxLevel
                    ? '최고 레벨'
                    : '${progress.levelXp} / ${progress.nextLevelXp} XP',
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: caption,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(
            begin: from ?? progress.fraction,
            end: progress.fraction,
          ),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              color: AppColors.blue,
              backgroundColor: AppColors.blueSoft,
              semanticsLabel: '레벨 진행도',
              semanticsValue: '${(progress.fraction * 100).round()}%',
            ),
          ),
        ),
        if (!progress.isMaxLevel) ...[
          const SizedBox(height: 4),
          Text(
            '다음 레벨까지 ${progress.remainingXp} XP',
            style: caption?.copyWith(color: AppColors.gray),
          ),
        ],
      ],
    );
  }
}
