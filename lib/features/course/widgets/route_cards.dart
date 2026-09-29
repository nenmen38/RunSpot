import 'package:flutter/material.dart';
import 'package:runquest/features/course/models/route_plan.dart';
import 'package:runquest/features/course/widgets/route_map.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/badge_pill.dart';
import 'package:runquest/shared/widgets/panel.dart';

class RouteCard extends StatelessWidget {
  const RouteCard({required this.plan, required this.onCourseTap, super.key});

  final RoutePlan plan;
  final VoidCallback onCourseTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              BadgePill(text: plan.distance),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: RouteMapPreview(plan: plan)),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final entry in plan.scores.entries) ...[
                Expanded(
                  child: ScoreMini(label: entry.key, score: entry.value),
                ),
                if (entry.key != plan.scores.keys.last)
                  const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onCourseTap,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('코스 다시 만들기'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CompactPlanCard extends StatelessWidget {
  const CompactPlanCard({required this.plan, super.key});

  final RoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(plan.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  plan.mission,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                const BadgePill(text: '기록 인증 ON'),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: 116, child: RouteMapPreview(plan: plan)),
        ],
      ),
    );
  }
}

class ScoreMini extends StatelessWidget {
  const ScoreMini({required this.label, required this.score, super.key});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.gray,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              color: AppColors.blue,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
