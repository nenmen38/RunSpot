import 'package:flutter/material.dart';

import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/account_query_panel.dart';
import '../../../shared/formatters/run_format.dart';
import '../data/statistics_service.dart';
import '../models/run_statistics.dart';

class QuickStats extends StatelessWidget {
  const QuickStats({required this.service, super.key});
  final StatisticsService service;

  @override
  Widget build(BuildContext context) => AccountQueryPanel<RunStatistics>(
    source: service,
    load: service.load,
    isCurrentOwner: () => service.isCurrentOwner,
    errorMessage: '개인 통계를 불러오지 못했습니다.',
    builder: (context, stats) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: '이번 주 거리',
                value:
                    '${(stats.weeklyDistanceMeters / 1000).toStringAsFixed(1)}km',
                icon: Icons.calendar_month,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: '누적 페이스',
                value: formatPaceDuration(stats.averagePace),
                icon: Icons.speed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatCard(
                label: '완료 러닝',
                value: '${stats.completedRuns}회',
                icon: Icons.flag_outlined,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
