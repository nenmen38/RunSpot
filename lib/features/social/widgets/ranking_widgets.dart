import 'package:flutter/material.dart';
import 'package:runquest/features/social/models/runner_rank.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class RankRow extends StatelessWidget {
  const RankRow({required this.runner, super.key});

  final RunnerRank runner;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: runner.isMe ? AppColors.blueSoft : AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '#${runner.rank}',
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  runner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  runner.badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.gray,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            runner.value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class TinyTab extends StatelessWidget {
  const TinyTab({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.blue : AppColors.line),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.gray,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
