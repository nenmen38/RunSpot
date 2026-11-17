import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';
import '../settings/appearance/app_appearance.dart';

/// 목표는 서버 계정별로 저장하고 같은 계정의 마지막 값을 기기에 보관합니다.
class WeeklyGoal extends ChangeNotifier {
  WeeklyGoal({AppearanceStore? store}) : _given = store;
  static final instance = WeeklyGoal();
  static const choices = [5, 10, 15, 20, 30, 40, 50];
  final AppearanceStore? _given;
  late final AppearanceStore _store = _given ?? DeviceAppearanceStore();
  SupabaseClient? _client;
  String? _owner;
  int _generation = 0;
  bool busy = false;
  String? error;
  int? kilometers;
  String get _key => _client == null
      ? 'run.weekly_goal_km'
      : 'run.weekly_goal.${_client!.rest.url}.$_owner';

  void bind(SupabaseClient client) {
    _client = client;
    _owner = client.auth.currentUser?.id;
    _generation++;
    kilometers = null;
    error = null;
    busy = false;
    load();
  }

  void unbind() {
    _generation++;
    _client = null;
    _owner = null;
    kilometers = null;
    error = null;
    busy = false;
  }

  Future<int?> _remote({bool update = false, int? value}) async {
    final client = _client!;
    final session = client.auth.currentSession;
    if (session == null || session.user.id != _owner) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    final result = await client
        .rpc(
          'my_weekly_goal',
          params: {'update_goal': update, 'kilometers': value},
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (client.auth.currentUser?.id != _owner) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    return (result as num?)?.toInt();
  }

  Future<void> load() async {
    if (busy) return;
    final generation = _generation;
    final key = _key;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final cached = int.tryParse(await _store.read(key) ?? '');
      if (generation != _generation) return;
      kilometers = cached != null && cached > 0 && cached <= 500
          ? cached
          : null;
      if (_client != null) {
        final value = await _remote();
        if (generation != _generation) return;
        kilometers = value;
        await _store.write(key, value?.toString() ?? '');
      }
    } catch (_) {
      if (generation == _generation) error = '목표를 동기화하지 못했습니다. 다시 시도해 주세요.';
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> set(int? value) async {
    if (busy || kilometers == value) return;
    if (value != null && (value < 1 || value > 500)) {
      throw ArgumentError('목표 범위가 올바르지 않습니다.');
    }
    final generation = _generation;
    final key = _key;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (_client != null) await _remote(update: true, value: value);
      if (generation != _generation) return;
      kilometers = value;
      await _store.write(key, value?.toString() ?? '');
    } catch (_) {
      if (generation == _generation) error = '목표를 저장하지 못했습니다. 다시 시도해 주세요.';
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
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
    if (picked != null) {
      await goal.set(picked == 0 ? null : picked);
      if (context.mounted && goal.error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(goal.error!)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = this.goal ?? WeeklyGoal.instance;
    return ListenableBuilder(
      listenable: goal,
      builder: (context, _) {
        if (goal.busy) return const LinearProgressIndicator();
        if (goal.error != null) {
          return TextButton(onPressed: goal.load, child: Text(goal.error!));
        }
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
