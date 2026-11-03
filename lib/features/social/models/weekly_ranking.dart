import 'runner_rank.dart';

enum RankingCategory {
  distance('주간 거리'),
  longest('최장 거리'),
  fiveK('5km 기록');

  const RankingCategory(this.label);
  final String label;
  String get code => this == fiveK ? 'five_k' : name;
}

enum RankingAudience { friends, all }

/// 공개·차단 정책을 통과한 사용자들의 기준별 순위입니다.
class WeeklyRanking {
  const WeeklyRanking({
    required this.canInteract,
    required this.weekStartedAt,
    required this.entries,
  });

  final bool canInteract;
  final DateTime weekStartedAt;
  final List<RunnerRank> entries;

  factory WeeklyRanking.fromJson(
    Map<String, dynamic> json, {
    RankingCategory category = RankingCategory.distance,
  }) {
    final allowed = json['can_interact'];
    final week = DateTime.tryParse(json['week_started_at'] as String? ?? '');
    final entries = json['entries'];
    if (allowed is! bool ||
        week == null ||
        entries is! List ||
        (!allowed && entries.isNotEmpty)) {
      throw const FormatException('랭킹 응답이 올바르지 않습니다.');
    }
    return WeeklyRanking(
      canInteract: allowed,
      weekStartedAt: week,
      entries: List.unmodifiable(
        entries.map((value) {
          final row = Map<String, dynamic>.from(value as Map);
          final rank = row['rank'];
          final nickname = row['nickname'];
          final distance = row['score'] ?? row['distance_m'];
          final isMe = row['is_me'];
          if (rank is! int ||
              rank < 0 ||
              nickname is! String ||
              nickname.isEmpty ||
              distance is! int ||
              distance < 0 ||
              isMe is! bool) {
            throw const FormatException('순위 항목이 올바르지 않습니다.');
          }
          return RunnerRank(
            rank,
            isMe ? '$nickname (나)' : nickname,
            switch (category) {
              RankingCategory.distance => '이번 주 누적 거리',
              RankingCategory.longest => '이번 주 최장 거리',
              RankingCategory.fiveK => '5km 최고 기록',
            },
            switch (category) {
              RankingCategory.distance =>
                '${(distance / 1000).toStringAsFixed(1)}km',
              RankingCategory.longest =>
                '${(distance / 1000).toStringAsFixed(1)}km',
              RankingCategory.fiveK =>
                distance == 0
                    ? '기록 없음'
                    : '${distance ~/ 60000000}:${((distance ~/ 1000000) % 60).toString().padLeft(2, '0')}',
            },
            isMe,
          );
        }),
      ),
    );
  }
}
