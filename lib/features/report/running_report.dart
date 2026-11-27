import 'package:supabase_flutter/supabase_flutter.dart';

enum ReportPeriod { month, year }

/// 한 달 또는 한 해 동안의 러닝 리포트입니다(서버 my_running_report 결과).
class RunningReport {
  RunningReport({
    required this.period,
    required this.starts,
    required this.runs,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.activeDays,
    required this.previousDistanceMeters,
    required this.buckets,
    this.longestMeters,
    this.longestAt,
    this.fastestPaceSeconds,
    this.favoriteWeekday,
    this.favoriteTime,
    this.companions = 0,
  });

  factory RunningReport.fromJson(Map<String, dynamic> json) {
    final longest = json['longest'] as Map?;
    return RunningReport(
      period: json['period'] == 'year' ? ReportPeriod.year : ReportPeriod.month,
      starts: DateTime.parse(json['starts'] as String),
      runs: (json['runs'] as num?)?.toInt() ?? 0,
      distanceMeters: (json['distance_m'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_sec'] as num?)?.toInt() ?? 0,
      activeDays: (json['active_days'] as num?)?.toInt() ?? 0,
      previousDistanceMeters:
          (json['previous_distance_m'] as num?)?.toInt() ?? 0,
      buckets: [
        for (final value in json['buckets'] as List? ?? const [])
          (value as num).toInt(),
      ],
      longestMeters: (longest?['distance_m'] as num?)?.toInt(),
      longestAt: switch (longest?['ended_at']) {
        final String at => DateTime.parse(at).toLocal(),
        _ => null,
      },
      fastestPaceSeconds: (json['fastest_pace_sec'] as num?)?.toInt(),
      favoriteWeekday: (json['favorite_weekday'] as num?)?.toInt(),
      favoriteTime: json['favorite_time'] as String?,
      companions: (json['companions'] as num?)?.toInt() ?? 0,
    );
  }

  final ReportPeriod period;
  final DateTime starts;
  final int runs;
  final int distanceMeters;
  final int durationSeconds;
  final int activeDays;
  final int previousDistanceMeters;

  /// 연간은 1~12월, 월간은 1~5주차마다 달린 거리(m)입니다.
  final List<int> buckets;
  final int? longestMeters;
  final DateTime? longestAt;
  final int? fastestPaceSeconds;

  /// 1=월요일 … 7=일요일입니다.
  final int? favoriteWeekday;

  /// morning·afternoon·evening·night 중 하나입니다.
  final String? favoriteTime;
  final int companions;

  bool get isEmpty => runs == 0;
  double get kilometers => distanceMeters / 1000;

  /// 기간 이름입니다(예: '2026년', '11월').
  String get title =>
      period == ReportPeriod.year ? '${starts.year}년' : '${starts.month}월';

  /// 지난 기간 이름입니다(예: '작년', '지난달').
  String get previousTitle => period == ReportPeriod.year ? '작년' : '지난달';

  /// 가장 많이 달린 칸(달·주차)의 번호(1부터)입니다. 기록이 없으면 null입니다.
  int? get bestBucket {
    var best = -1, index = -1;
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i] > best) {
        best = buckets[i];
        index = i;
      }
    }
    return best > 0 ? index + 1 : null;
  }

  String bucketLabel(int number) =>
      period == ReportPeriod.year ? '$number월' : '$number주차';
}

abstract interface class RunningReportService {
  Future<RunningReport> load(ReportPeriod period, DateTime starts);
}

class SupabaseRunningReportService implements RunningReportService {
  SupabaseRunningReportService(this.client);
  final SupabaseClient client;

  @override
  Future<RunningReport> load(ReportPeriod period, DateTime starts) async {
    final result = await client.rpc(
      'my_running_report',
      params: {
        'period': period.name,
        'starts':
            '${starts.year.toString().padLeft(4, '0')}-${starts.month.toString().padLeft(2, '0')}-01',
      },
    );
    return RunningReport.fromJson(Map<String, dynamic>.from(result as Map));
  }
}

/// 12월·1월에는 연말 결산을 먼저 보여 줍니다. 1월에는 지난해 결산입니다.
({ReportPeriod period, DateTime starts}) defaultReport(DateTime now) =>
    switch (now.month) {
      12 => (period: ReportPeriod.year, starts: DateTime(now.year)),
      1 => (period: ReportPeriod.year, starts: DateTime(now.year - 1)),
      _ => (period: ReportPeriod.month, starts: DateTime(now.year, now.month)),
    };
