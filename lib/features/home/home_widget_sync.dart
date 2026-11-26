import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../profile/weekly_goal.dart';
import '../run_history/models/run_record.dart';
import '../run_history/run_history_controller.dart';

/// 홈 화면 위젯에 보여 줄 이번 주 기록입니다.
@immutable
class HomeWidgetData {
  const HomeWidgetData({
    required this.weekMeters,
    required this.runs,
    this.goalKm,
  });

  final int weekMeters;
  final int runs;
  final int? goalKm;

  String get weekKm => (weekMeters / 1000).toStringAsFixed(1);

  /// 목표 대비 진행률(0~100)입니다. 목표가 없으면 0입니다.
  int get percent {
    final goal = goalKm;
    if (goal == null || goal <= 0) return 0;
    return (weekMeters / (goal * 1000) * 100).floor().clamp(0, 100);
  }

  /// 이번 주(월요일 0시부터, 폰 시간 기준)에 끝난 기록만 더합니다.
  static HomeWidgetData from(
    Iterable<RunRecord> records, {
    int? goalKm,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final monday = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - DateTime.monday));
    var meters = 0;
    var runs = 0;
    for (final record in records) {
      if (record.endedAt.toLocal().isBefore(monday)) continue;
      meters += record.distanceMeters;
      runs++;
    }
    return HomeWidgetData(weekMeters: meters, runs: runs, goalKm: goalKm);
  }

  Map<String, Object> toArguments() => {
    'weekKm': weekKm,
    'goalKm': goalKm ?? 0,
    'percent': percent,
    'runs': runs,
  };

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetData &&
      other.weekMeters == weekMeters &&
      other.runs == runs &&
      other.goalKm == goalKm;

  @override
  int get hashCode => Object.hash(weekMeters, runs, goalKm);
}

/// 러닝 기록이나 주간 목표가 바뀌면 안드로이드 홈 화면 위젯을 새로 그립니다.
/// 같은 내용이면 다시 보내지 않고, 위젯이 없는 기기(iOS·테스트)에서는 조용히 넘어갑니다.
class HomeWidgetSync {
  HomeWidgetSync({
    required this.history,
    WeeklyGoal? goal,
    this.channel = const MethodChannel('runspot/home_widget'),
    bool? enabled,
  }) : goal = goal ?? WeeklyGoal.instance,
       _enabled =
           enabled ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final RunHistoryController history;
  final WeeklyGoal goal;
  final MethodChannel channel;
  final bool _enabled;
  HomeWidgetData? _sent;
  Timer? _debounce;

  void start() {
    if (!_enabled) return;
    history.addListener(_schedule);
    goal.addListener(_schedule);
    _schedule();
  }

  void dispose() {
    _debounce?.cancel();
    history.removeListener(_schedule);
    goal.removeListener(_schedule);
  }

  void _schedule() {
    _debounce?.cancel();
    // 기록을 불러오는 동안 여러 번 바뀌어도 한 번만 보냅니다.
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(push()),
    );
  }

  @visibleForTesting
  Future<void> push() async {
    final data = HomeWidgetData.from(
      history.visibleRecords,
      goalKm: goal.kilometers,
    );
    if (data == _sent) return;
    try {
      await channel.invokeMethod<void>('update', data.toArguments());
      _sent = data;
    } on MissingPluginException {
      // 위젯을 지원하지 않는 환경입니다.
    } on PlatformException {
      // 위젯 갱신에 실패해도 앱 사용에는 영향이 없습니다.
    }
  }
}
