import 'runner_rank.dart';

/// 공개 정책을 통과한 친구와 본인의 주간 거리 순위입니다.
class WeeklyRanking {
  const WeeklyRanking({
    required this.canInteract,
    required this.weekStartedAt,
    required this.entries,
  });

  final bool canInteract;
  final DateTime weekStartedAt;
  final List<RunnerRank> entries;

  factory WeeklyRanking.fromJson(Map<String, dynamic> json) {
    final allowed = json['can_interact'];
    final week = DateTime.tryParse(json['week_started_at'] as String? ?? '');
    final entries = json['entries'];
    if (allowed is! bool ||
        week == null ||
        entries is! List ||
        (!allowed && entries.isNotEmpty)) {
      throw const FormatException('친구 랭킹 응답이 올바르지 않습니다.');
    }
    return WeeklyRanking(
      canInteract: allowed,
      weekStartedAt: week,
      entries: List.unmodifiable(
        entries.map((value) {
          final row = Map<String, dynamic>.from(value as Map);
          final rank = row['rank'];
          final nickname = row['nickname'];
          final distance = row['distance_m'];
          final isMe = row['is_me'];
          if (rank is! int ||
              rank < 1 ||
              nickname is! String ||
              nickname.isEmpty ||
              distance is! int ||
              distance < 0 ||
              isMe is! bool) {
            throw const FormatException('친구 순위 항목이 올바르지 않습니다.');
          }
          return RunnerRank(
            rank,
            isMe ? '$nickname (나)' : nickname,
            '이번 주 누적 거리',
            '${(distance / 1000).toStringAsFixed(1)}km',
            isMe,
          );
        }),
      ),
    );
  }
}
