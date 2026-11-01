/// 한국 시간 기준 월별 거리와 완성된 1km 구간에 근거한 개인 기록입니다.
class RunGrowth {
  const RunGrowth({
    required this.months,
    required this.longest,
    required this.best5k,
    required this.best10k,
  });

  final List<MonthlyDistance> months;
  final PersonalBest? longest;
  final PersonalBest? best5k;
  final PersonalBest? best10k;

  factory RunGrowth.fromJson(Object? value) {
    final json = _object(value);
    final rows = json['monthly_distances'];
    if (rows is! List || rows.length != 12) _invalid();
    final months = rows.map(MonthlyDistance.fromJson).toList();
    for (var i = 1; i < months.length; i++) {
      final previous = months[i - 1];
      final expected = DateTime.utc(previous.year, previous.month + 1);
      if (months[i].year != expected.year ||
          months[i].month != expected.month) {
        _invalid();
      }
    }
    return RunGrowth(
      months: List.unmodifiable(months),
      longest: PersonalBest.decode(json['longest_run'], 'distance_m'),
      best5k: PersonalBest.decode(json['best_5k'], 'duration_us'),
      best10k: PersonalBest.decode(json['best_10k'], 'duration_us'),
    );
  }
}

class MonthlyDistance {
  const MonthlyDistance(this.year, this.month, this.distanceMeters, this.runs);
  final int year;
  final int month;
  final int distanceMeters;
  final int runs;

  factory MonthlyDistance.fromJson(Object? value) {
    final json = _object(value);
    final label = json['month'];
    if (label is! String ||
        !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(label)) {
      _invalid();
    }
    return MonthlyDistance(
      int.parse(label.substring(0, 4)),
      int.parse(label.substring(5)),
      _integer(json['distance_m']),
      _integer(json['completed_runs']),
    );
  }
}

class PersonalBest {
  const PersonalBest(this.value, this.endedAt);
  final int value;
  final DateTime endedAt;

  static PersonalBest? decode(Object? value, String field) {
    if (value == null) return null;
    final json = _object(value);
    final date = json['ended_at'];
    final endedAt = date is String ? DateTime.tryParse(date) : null;
    final amount = _integer(json[field]);
    if (endedAt == null || !endedAt.isUtc || amount == 0) _invalid();
    return PersonalBest(amount, endedAt);
  }

  String get koreanDate {
    final date = endedAt.toUtc().add(const Duration(hours: 9));
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  // 초 미만의 측정값을 버려 실제보다 빠른 기록으로 표시하지 않습니다.
  Duration get duration => Duration(seconds: (value / 1000000).ceil());
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) _invalid();
  return value;
}

int _integer(Object? value) {
  if (value is! int || value < 0) _invalid();
  return value;
}

Never _invalid() => throw const FormatException('성장 추이 응답이 올바르지 않습니다.');
