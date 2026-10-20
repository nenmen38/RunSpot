/// 서버에 저장된 기록의 주간 거리와 누적 통계입니다.
class RunStatistics {
  const RunStatistics({
    required this.weekStartedAt,
    required this.weeklyDistanceMeters,
    required this.completedRuns,
    required this.paceDistanceMeters,
    required this.paceDurationSeconds,
  });

  final DateTime weekStartedAt;
  final int weeklyDistanceMeters;
  final int completedRuns;
  final int paceDistanceMeters;
  final int paceDurationSeconds;

  Duration? get averagePace => paceDistanceMeters > 0 && paceDurationSeconds > 0
      ? Duration(
          seconds: (paceDurationSeconds * 1000 / paceDistanceMeters).round(),
        )
      : null;

  factory RunStatistics.fromJson(Map<String, dynamic> json) {
    final week = DateTime.tryParse(json['week_started_at'] as String? ?? '');
    final values = [
      json['weekly_distance_m'],
      json['completed_runs'],
      json['pace_distance_m'],
      json['pace_duration_sec'],
    ];
    if (week == null || values.any((v) => v is! int || v < 0)) {
      throw const FormatException('개인 통계 응답이 올바르지 않습니다.');
    }
    return RunStatistics(
      weekStartedAt: week,
      weeklyDistanceMeters: values[0] as int,
      completedRuns: values[1] as int,
      paceDistanceMeters: values[2] as int,
      paceDurationSeconds: values[3] as int,
    );
  }
}
