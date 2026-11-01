import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/panel.dart';
import '../models/run_growth.dart';

class RunGrowthPanel extends StatefulWidget {
  const RunGrowthPanel({required this.growth, super.key});
  final RunGrowth growth;

  @override
  State<RunGrowthPanel> createState() => _RunGrowthPanelState();
}

class _RunGrowthPanelState extends State<RunGrowthPanel> {
  String? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final months = widget.growth.months;
    final selected = months.firstWhere(
      (m) => '${m.year}-${m.month}' == _selectedMonth,
      orElse: () => months.last,
    );
    final maximum = math.max(
      1,
      months.map((m) => m.distanceMeters).reduce(math.max),
    );
    final index = months.indexOf(selected);
    final previous = index > 0 ? months[index - 1] : null;
    final difference = previous == null
        ? null
        : selected.distanceMeters - previous.distanceMeters;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('개인 기록과 성장 추이', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('${selected.year}년 ${selected.month}월 · ${selected.runs}회'),
          Text(
            '${(selected.distanceMeters / 1000).toStringAsFixed(2)}km',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (difference != null)
            Text(
              '지난달 전체 대비 ${difference > 0 ? '+' : ''}${(difference / 1000).toStringAsFixed(2)}km',
            ),
          const SizedBox(height: 4),
          const Text('최근 12개월 · 이번 달은 현재까지의 기록입니다.'),
          const SizedBox(height: 12),
          SizedBox(
            height: 156,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final month in months)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: identical(month, selected),
                      label:
                          '${month.year}년 ${month.month}월 ${(month.distanceMeters / 1000).toStringAsFixed(2)}킬로미터 ${month.runs}회',
                      child: InkWell(
                        onTap: () => setState(
                          () => _selectedMonth = '${month.year}-${month.month}',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    height: math.max(
                                      2,
                                      112 * month.distanceMeters / maximum,
                                    ),
                                    decoration: BoxDecoration(
                                      color: identical(month, selected)
                                          ? AppColors.blue
                                          : AppColors.blueSoft,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${month.month}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _best(context, '최장 거리', widget.growth.longest, distance: true),
          _best(context, '5km 최고 기록', widget.growth.best5k),
          _best(context, '10km 최고 기록', widget.growth.best10k),
        ],
      ),
    );
  }

  Widget _best(
    BuildContext context,
    String label,
    PersonalBest? best, {
    bool distance = false,
  }) {
    final value = best == null
        ? '기록 없음'
        : distance
        ? '${(best.value / 1000).toStringAsFixed(2)}km'
        : formatRunDuration(best.duration);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(label),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          if (best != null) Text(best.koreanDate),
        ],
      ),
    );
  }
}
