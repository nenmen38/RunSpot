import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../settings/appearance/app_appearance.dart';

/// 이번 주에 달릴 목표 거리(km)입니다. 이 폰에 저장합니다. 정하지 않았으면 null입니다.
class WeeklyGoal extends ChangeNotifier {
  WeeklyGoal({AppearanceStore? store}) : _given = store;

  static final instance = WeeklyGoal();
  static const _key = 'run.weekly_goal_km';
  static const choices = [5, 10, 15, 20, 30, 40, 50];

  final AppearanceStore? _given;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();

  int? kilometers;

  Future<void> load() async {
    try {
      final value = int.tryParse(await _store.read(_key) ?? '');
      kilometers = value != null && value > 0 && value <= 500 ? value : null;
      notifyListeners();
    } catch (_) {}
  }

  /// [value]가 null이면 목표를 지웁니다.
  Future<void> set(int? value) async {
    if (kilometers == value) return;
    kilometers = value;
    notifyListeners();
    try {
      await _store.write(_key, value?.toString() ?? '');
    } catch (_) {}
  }
}

/// 프로필의 주간 목표 진행 막대입니다. 예: "이번 주 20km 중 12.4km"
class WeeklyGoalBar extends StatelessWidget {
  const WeeklyGoalBar({
    required this.weeklyDistanceMeters,
    this.goal,
    super.key,
  });

  final int weeklyDistanceMeters;
  final WeeklyGoal? goal;

  Future<void> _choose(BuildContext context, WeeklyGoal goal) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('주간 목표 거리', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final km in WeeklyGoal.choices)
                    ChoiceChip(
                      label: Text('${km}km'),
                      selected: goal.kilometers == km,
                      onSelected: (_) => Navigator.pop(context, km),
                    ),
                ],
              ),
              if (goal.kilometers != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, 0),
                  child: const Text('목표 지우기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (picked != null) await goal.set(picked == 0 ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final goal = this.goal ?? WeeklyGoal.instance;
    return ListenableBuilder(
      listenable: goal,
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final done = weeklyDistanceMeters / 1000;
        final target = goal.kilometers;
        if (target == null) {
          return OutlinedButton.icon(
            onPressed: () => _choose(context, goal),
            icon: const Icon(Icons.flag_outlined),
            label: const Text('주간 목표 정하기'),
          );
        }
        final progress = (done / target).clamp(0.0, 1.0);
        final reached = done >= target;
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _choose(context, goal),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '이번 주 ${target}km 중 ${done.toStringAsFixed(1)}km',
                        style: text.titleMedium,
                      ),
                    ),
                    Text(
                      reached ? '달성!' : '${(progress * 100).floor()}%',
                      style: text.labelLarge?.copyWith(
                        color: reached ? AppColors.green : AppColors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: AppColors.line,
                    color: reached ? AppColors.green : AppColors.blue,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reached
                      ? '목표를 이뤘어요. 눌러서 목표를 바꿀 수 있어요.'
                      : '${(target - done).toStringAsFixed(1)}km 남았어요.',
                  style: text.bodySmall?.copyWith(color: AppColors.gray),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
