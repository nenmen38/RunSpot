import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/badge_pill.dart';
import '../../../shared/widgets/page_layout.dart';
import '../../../shared/widgets/panel.dart';

enum TrainingPlanKind {
  habit('habit', '러닝 습관 만들기', '10~25분 걷기·달리기', Icons.directions_walk),
  fiveK('5k', '5km 준비', '2km부터 5km까지', Icons.directions_run),
  tenK('10k', '10km 준비', '5km부터 10km까지', Icons.route_outlined);

  const TrainingPlanKind(this.id, this.title, this.subtitle, this.icon);

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  String targetForWeek(int week) => switch (this) {
    habit => '${10 + week * 5}분 걷기·달리기',
    fiveK => '${[2, 3, 4, 5][week]}km 편안하게',
    tenK => '${[5, 6, 8, 10][week]}km 편안하게',
  };
}

class TrainingPlanChoices extends StatelessWidget {
  const TrainingPlanChoices({required this.onSelect, super.key});

  final ValueChanged<TrainingPlanKind> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: '훈련 목표 선택',
          subtitle: '4주 일정 · 주 3회',
          icon: Icons.calendar_month_outlined,
        ),
        const SizedBox(height: 8),
        Text('목표를 선택하고 시작일을 정하면 훈련 일정이 만들어집니다.', style: text.bodyMedium),
        const SizedBox(height: 16),
        for (final kind in TrainingPlanKind.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.blueSoft,
                    foregroundColor: AppColors.blueText,
                    child: Icon(kind.icon, size: 20),
                  ),
                  title: Text(kind.title, style: text.titleMedium),
                  subtitle: Text(kind.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onSelect(kind),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class TrainingPlanSchedule extends StatelessWidget {
  const TrainingPlanSchedule({
    required this.kind,
    required this.start,
    required this.completed,
    required this.onSessionTap,
    super.key,
  });

  final TrainingPlanKind kind;
  final DateTime start;
  final Set<int> completed;
  final ValueChanged<int>? onSessionTap;

  static const _weekCount = 4;
  static const _sessionsPerWeek = 3;
  static const _total = _weekCount * _sessionsPerWeek;

  bool _weekDone(int week) => Iterable<int>.generate(
    _sessionsPerWeek,
    (day) => week * _sessionsPerWeek + day,
  ).every(completed.contains);

  @override
  Widget build(BuildContext context) {
    final progress = completed.length / _total;
    final nextWeek = Iterable<int>.generate(_weekCount)
        .where((week) => !_weekDone(week))
        .firstOrNull;
    final dates = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: kind.title,
                subtitle: '${dates.formatMediumDate(start)} 시작',
                icon: kind.icon,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('전체 진행', style: Theme.of(context).textTheme.titleMedium),
                  BadgePill(text: '완료 ${completed.length} / $_total회'),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                color: progress == 1 ? AppColors.green : AppColors.blue,
                backgroundColor: AppColors.line,
                semanticsLabel: '훈련 계획 진행률',
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text('주차별 일정', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        for (var week = 0; week < _weekCount; week++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              padding: EdgeInsets.zero,
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  key: ValueKey((kind, start, week)),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  initiallyExpanded: week == nextWeek,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                  title: Text(
                    '${week + 1}주차',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    '${kind.targetForWeek(week)} · ${_weekDone(week) ? '완료' : '3회 일정'}',
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  children: [
                    for (var day = 0; day < _sessionsPerWeek; day++) ...[
                      const Divider(height: 1),
                      _TrainingSessionRow(
                        day: day,
                        date: DateTime(
                          start.year,
                          start.month,
                          start.day + week * 7 + day * 2,
                        ),
                        done: completed.contains(week * _sessionsPerWeek + day),
                        onTap: onSessionTap == null
                            ? null
                            : () =>
                                  onSessionTap!(week * _sessionsPerWeek + day),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TrainingSessionRow extends StatelessWidget {
  const _TrainingSessionRow({
    required this.day,
    required this.date,
    required this.done,
    required this.onTap,
  });

  final int day;
  final DateTime date;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final action = TextButton.icon(
      onPressed: onTap,
      icon: Icon(done ? Icons.link_off : Icons.add_link, size: 18),
      label: Text(done ? '연결 해제' : '기록 연결'),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            MediaQuery.textScalerOf(context).scale(14) * 17 >
            constraints.maxWidth;
        final label = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${day + 1}회차', style: Theme.of(context).textTheme.titleSmall),
            Text(
              '${MaterialLocalizations.of(context).formatCompactDate(date)} · ${done ? '완료' : '예정'}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.gray),
            ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: stack
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    label,
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    action,
                  ],
                ),
        );
      },
    );
  }
}
