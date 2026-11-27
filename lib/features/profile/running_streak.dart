import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 주간 목표(목표가 없으면 주 1회 이상 달리기)를 몇 주 연속 지켰는지입니다.
@immutable
class RunningStreak {
  const RunningStreak({
    required this.weeks,
    required this.goalBased,
    required this.thisWeekDone,
    this.thisWeekMeters = 0,
    this.goalMeters,
    this.daysSinceLastRun,
  });

  factory RunningStreak.fromJson(Map<String, dynamic> json) => RunningStreak(
    weeks: (json['weeks'] as num?)?.toInt() ?? 0,
    goalBased: json['goal_based'] == true,
    thisWeekDone: json['this_week_done'] == true,
    thisWeekMeters: (json['this_week_m'] as num?)?.toInt() ?? 0,
    goalMeters: (json['goal_m'] as num?)?.toInt(),
    daysSinceLastRun: (json['days_since_last_run'] as num?)?.toInt(),
  );

  final int weeks;
  final bool goalBased;
  final bool thisWeekDone;
  final int thisWeekMeters;
  final int? goalMeters;
  final int? daysSinceLastRun;

  /// 짧은 이름표입니다(예: '🔥 3주 연속 목표 달성').
  String get label => goalBased ? '🔥 $weeks주 연속 목표 달성' : '🔥 $weeks주 연속 달리는 중';

  /// 이번 주에 무엇을 하면 이어지는지 알려 줍니다.
  String get hint {
    if (thisWeekDone) {
      return goalBased ? '이번 주 목표도 달성했어요!' : '이번 주도 달렸어요!';
    }
    if (goalBased && goalMeters != null) {
      final left = ((goalMeters! - thisWeekMeters) / 1000).clamp(0, 9999);
      return '이번 주 ${left.toStringAsFixed(1)}km 더 달리면 ${weeks + 1}주 연속이에요';
    }
    return '이번 주에 한 번 달리면 ${weeks + 1}주 연속이에요';
  }
}

/// 연속 기록을 서버에서 읽어 두고 화면들(프로필·홈 위젯)이 함께 씁니다.
class RunningStreakStore extends ChangeNotifier {
  RunningStreakStore._();
  static final instance = RunningStreakStore._();

  Future<RunningStreak> Function()? _load;
  RunningStreak? streak;
  int _generation = 0;
  Timer? _debounce;

  void bind(SupabaseClient client) => bindLoader(
    () async => RunningStreak.fromJson(
      Map<String, dynamic>.from(await client.rpc('my_running_streak') as Map),
    ),
  );

  @visibleForTesting
  void bindLoader(Future<RunningStreak> Function() load) {
    _load = load;
    streak = null;
    _generation++;
    unawaited(refresh());
  }

  void unbind() {
    _debounce?.cancel();
    _load = null;
    streak = null;
    _generation++;
    notifyListeners();
  }

  /// 러닝 기록이 바뀌면 잠시 뒤 한 번만 다시 읽습니다.
  void refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(refresh()));
  }

  Future<void> refresh() async {
    final load = _load;
    if (load == null) return;
    final generation = ++_generation;
    try {
      final value = await load().timeout(const Duration(seconds: 15));
      if (generation != _generation) return;
      streak = value;
      notifyListeners();
    } catch (_) {
      // 연속 기록은 덤입니다. 못 읽으면 보여 주지 않습니다.
    }
  }
}

/// 프로필의 연속 기록 카드입니다. 2주 이상 이어졌거나 이번 주에 이어 갈 수 있을 때 보여 줍니다.
class RunningStreakCard extends StatelessWidget {
  const RunningStreakCard({this.store, super.key});

  final RunningStreakStore? store;

  @override
  Widget build(BuildContext context) {
    final source = store ?? RunningStreakStore.instance;
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final streak = source.streak;
        if (streak == null || streak.weeks < 1) return const SizedBox.shrink();
        final text = Theme.of(context).textTheme;
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Semantics(
            container: true,
            label: '${streak.label.replaceFirst('🔥 ', '')}. ${streak.hint}',
            child: ExcludeSemantics(
              child: Container(
                key: const ValueKey('running-streak'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF8A3D), Color(0xFFF65A5A)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Text(
                      '${streak.weeks}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            streak.label,
                            style: text.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            streak.hint,
                            style: text.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: .92),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (streak.thisWeekDone)
                      const Icon(Icons.check_circle, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
