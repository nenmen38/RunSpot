import 'package:runquest/features/profile/data/statistics_service.dart';
import 'package:runquest/features/profile/models/run_statistics.dart';
import 'package:runquest/features/social/data/ranking_service.dart';
import 'package:runquest/features/social/models/weekly_ranking.dart';

final statisticsJson = <String, dynamic>{
  'week_started_at': '2026-10-18T15:00:00Z',
  'weekly_distance_m': 12000,
  'completed_runs': 23,
  'pace_distance_m': 4000,
  'pace_duration_sec': 1500,
};
final rankingJson = <String, dynamic>{
  'can_interact': true,
  'week_started_at': '2026-10-18T15:00:00Z',
  'entries': [
    {'rank': 1, 'nickname': '친구러너', 'distance_m': 15000, 'is_me': false},
    {'rank': 2, 'nickname': '내닉네임', 'distance_m': 12000, 'is_me': true},
  ],
};

class FakeStatisticsService implements StatisticsService {
  @override
  bool isCurrentOwner = true;
  bool failed = false;
  int calls = 0;
  RunStatistics result = RunStatistics.fromJson(statisticsJson);
  Future<RunStatistics> Function()? onLoad;

  @override
  Future<RunStatistics> load() async {
    ++calls;
    if (failed) throw StateError('조회 실패');
    return onLoad == null ? result : await onLoad!();
  }
}

class FakeRankingService implements RankingService {
  @override
  bool isCurrentOwner = true;
  bool failed = false;
  int calls = 0;
  WeeklyRanking result = WeeklyRanking.fromJson(rankingJson);
  Future<WeeklyRanking> Function()? onLoad;

  @override
  Future<WeeklyRanking> load() async {
    ++calls;
    if (failed) throw StateError('조회 실패');
    return onLoad == null ? result : await onLoad!();
  }
}
