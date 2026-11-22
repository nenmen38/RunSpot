import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/badge_pill.dart';
import '../../shared/widgets/page_layout.dart';
import '../../shared/widgets/panel.dart';
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
    this.compact = false,
    super.key,
  });

  final int weeklyDistanceMeters;
  final WeeklyGoal? goal;
  final bool compact;

  Future<void> _choose(BuildContext context, WeeklyGoal goal) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WeeklyGoalPicker(current: goal.kilometers),
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
        final theme = Theme.of(context);
        final distance = weeklyDistanceMeters / 1000;
        final target = goal.kilometers;
        final progress = target == null
            ? 0.0
            : (distance / target).clamp(0.0, 1.0);
        final reached = progress == 1;
        if (compact && !goal.busy && goal.error == null) {
          return Panel(
            padding: EdgeInsets.zero,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _choose(context, goal),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SectionHeader(
                              title: '주간 목표',
                              subtitle: target == null
                                  ? '이번 주 ${distance.toStringAsFixed(1)}km · 목표 정하기'
                                  : '${distance.toStringAsFixed(1)} / ${target}km${reached ? ' · 달성' : ''}',
                              icon: Icons.flag_outlined,
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      if (target != null) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(6),
                          backgroundColor: AppColors.line,
                          color: reached ? AppColors.green : AppColors.blue,
                          semanticsLabel: '주간 거리 목표 진행률',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: '주간 목표',
                subtitle: !goal.busy && target == null
                    ? '이번 주 ${distance.toStringAsFixed(1)}km'
                    : '이번 주 달린 거리',
                icon: Icons.flag_outlined,
              ),
              if (goal.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (goal.error case final error?)
                TextButton(onPressed: goal.load, child: Text(error)),
              if (!goal.busy && target == null) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => _choose(context, goal),
                  icon: const Icon(Icons.add),
                  label: const Text('주간 목표 정하기'),
                ),
              ],
              if (target != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${distance.toStringAsFixed(1)} / ${target}km',
                      style: theme.textTheme.headlineSmall,
                    ),
                    BadgePill(
                      text: reached ? '목표 달성' : '${(progress * 100).floor()}%',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  backgroundColor: AppColors.line,
                  color: reached ? AppColors.green : AppColors.blue,
                  semanticsLabel: '주간 거리 목표 진행률',
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        reached
                            ? '이번 주 목표를 달성했어요.'
                            : '${(target - distance).toStringAsFixed(1)}km 남았어요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.gray,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: goal.busy
                          ? null
                          : () => _choose(context, goal),
                      child: const Text('목표 변경'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WeeklyGoalPicker extends StatefulWidget {
  const _WeeklyGoalPicker({required this.current});
  final int? current;

  @override
  State<_WeeklyGoalPicker> createState() => _WeeklyGoalPickerState();
}

class _WeeklyGoalPickerState extends State<_WeeklyGoalPicker> {
  late int? _selected = widget.current;

  @override
  Widget build(BuildContext context) {
    final choices = {
      ...WeeklyGoal.choices,
      if (widget.current case final current?) current,
    }.toList()..sort();
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(
                title: '주간 목표 거리',
                subtitle: '한 주에 달릴 거리를 선택하세요.',
                icon: Icons.flag_outlined,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final km in choices)
                    ChoiceChip(
                      label: Text('${km}km'),
                      selected: _selected == km,
                      onSelected: (_) => setState(() => _selected = km),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _selected == null || _selected == widget.current
                    ? null
                    : () => Navigator.pop(context, _selected),
                child: const Text('목표 저장'),
              ),
              if (widget.current != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, 0),
                  child: const Text('목표 지우기'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
