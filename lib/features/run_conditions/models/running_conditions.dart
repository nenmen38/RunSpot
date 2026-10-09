enum RunningSuitability { good, caution, avoid, unknown }

class WeatherObservation {
  const WeatherObservation({
    required this.observedAt,
    this.temperature,
    this.rain,
    this.precipitation,
    this.wind,
  });
  final DateTime? observedAt;
  final double? temperature;
  final double? rain;
  final int? precipitation;
  final double? wind;

  factory WeatherObservation.fromJson(Map<String, dynamic> json) =>
      WeatherObservation(
        observedAt: _time(json['observedAt']),
        temperature: _number(json['temperature'], -80, 60),
        rain: _number(json['rain'], 0, 1000),
        precipitation: _integer(json['precipitation'], 0, 7),
        wind: _number(json['wind'], 0, 150),
      );

  String get precipitationLabel => switch (precipitation) {
    0 => '강수 없음',
    1 => '비',
    2 => '비·눈',
    3 => '눈',
    4 => '소나기',
    5 => '빗방울',
    6 => '빗방울·눈날림',
    7 => '눈날림',
    _ => '강수 정보 없음',
  };
}

class DustObservation {
  const DustObservation({
    required this.observedAt,
    required this.station,
    required this.distanceKm,
    this.pm10,
    this.pm25,
  });
  final DateTime? observedAt;
  final String station;
  final double distanceKm;
  final double? pm10;
  final double? pm25;

  factory DustObservation.fromJson(Map<String, dynamic> json) =>
      DustObservation(
        observedAt: _time(json['observedAt']),
        station: json['station'] is String ? json['station'] as String : '',
        distanceKm: _number(json['distanceKm'], 0, 30) ?? double.infinity,
        pm10: _number(json['pm10'], 0, 10000),
        pm25: _number(json['pm25'], 0, 10000),
      );

  static int? grade(double? value, {required bool fine}) {
    if (value == null) return null;
    final limits = fine ? [15, 35, 75] : [30, 80, 150];
    for (var i = 0; i < limits.length; i++) {
      if (value <= limits[i]) return i + 1;
    }
    return 4;
  }

  static String gradeLabel(int? grade) => switch (grade) {
    1 => '좋음',
    2 => '보통',
    3 => '나쁨',
    4 => '매우 나쁨',
    _ => '자료 없음',
  };
}

class RunningConditions {
  const RunningConditions({
    required this.fetchedAt,
    this.weather,
    this.dust,
    this.weatherError,
    this.dustError,
  });
  final DateTime fetchedAt;
  final WeatherObservation? weather;
  final DustObservation? dust;
  final String? weatherError;
  final String? dustError;

  factory RunningConditions.fromJson(Map<String, dynamic> json) {
    final time = _time(json['fetchedAt']);
    if (time == null) throw const FormatException('관측 자료 조회 시각이 없습니다.');
    final errors = json['errors'];
    return RunningConditions(
      fetchedAt: time,
      weather: json['weather'] is Map<String, dynamic>
          ? WeatherObservation.fromJson(json['weather'] as Map<String, dynamic>)
          : null,
      dust: json['dust'] is Map<String, dynamic>
          ? DustObservation.fromJson(json['dust'] as Map<String, dynamic>)
          : null,
      weatherError: errors is Map && errors['weather'] is String
          ? errors['weather'] as String
          : null,
      dustError: errors is Map && errors['dust'] is String
          ? errors['dust'] as String
          : null,
    );
  }

  static bool isFresh(DateTime? time, DateTime now) =>
      time != null &&
      now.difference(time) <= const Duration(hours: 2) &&
      time.difference(now) <= const Duration(minutes: 15);

  ConditionAssessment assess(DateTime now) {
    final notes = <String>[];
    var status = RunningSuitability.good;
    var incomplete = false;
    final w = weather, d = dust;
    if (w == null || !isFresh(w.observedAt, now)) {
      incomplete = true;
      notes.add(
        w == null ? '날씨 관측 자료를 가져오지 못했습니다.' : '날씨 관측 자료가 오래되었거나 시각이 올바르지 않습니다.',
      );
    } else {
      if (w.temperature == null ||
          w.wind == null ||
          w.rain == null ||
          w.precipitation == null) {
        incomplete = true;
      }
      // 기상 특보가 아니라 현재 관측값에 적용하는 앱의 참고 기준입니다.
      if (w.temperature != null &&
          (w.temperature! >= 30 || w.temperature! <= 0)) {
        status = RunningSuitability.caution;
        notes.add(
          w.temperature! >= 30
              ? '기온이 높습니다. 운동 강도와 시간을 줄이는 편이 좋습니다.'
              : '기온이 낮습니다. 보온과 미끄러운 노면에 주의해 주세요.',
        );
      }
      if (w.wind != null && w.wind! >= 8) {
        status = RunningSuitability.caution;
        notes.add('바람이 강합니다. 노출된 장소에서 주의해 주세요.');
      }
      if ((w.precipitation ?? 0) > 0 || (w.rain ?? 0) > 0) {
        status = RunningSuitability.caution;
        notes.add('강수가 관측되었습니다. 젖거나 미끄러운 노면에 주의해 주세요.');
      }
    }
    if (d == null ||
        !isFresh(d.observedAt, now) ||
        d.station.isEmpty ||
        !d.distanceKm.isFinite) {
      incomplete = true;
      notes.add(
        d == null
            ? '미세먼지 관측 자료를 가져오지 못했습니다.'
            : '미세먼지 관측 자료의 시각 또는 측정소를 확인할 수 없습니다.',
      );
    } else {
      if (d.pm10 == null || d.pm25 == null) {
        incomplete = true;
        notes.add('미세먼지 관측 항목 일부가 누락되었습니다.');
      }
      final grades = [
        DustObservation.grade(d.pm10, fine: false),
        DustObservation.grade(d.pm25, fine: true),
      ].whereType<int>();
      final worst = grades.fold(0, (a, b) => a > b ? a : b);
      if (worst >= 3) {
        status = worst == 4
            ? RunningSuitability.avoid
            : RunningSuitability.caution;
        notes.add('미세먼지 농도가 높습니다. 오래 달리거나 강도 높은 야외 운동은 피하는 편이 좋습니다.');
      }
    }
    if (incomplete && status == RunningSuitability.good) {
      status = RunningSuitability.unknown;
    }
    if (notes.isEmpty && incomplete) notes.add('일부 관측 항목이 없어 조건을 판단할 수 없습니다.');
    if (notes.isEmpty) notes.add('현재 관측된 날씨와 미세먼지 조건은 양호합니다.');
    return ConditionAssessment(status, notes, incomplete);
  }
}

class ConditionAssessment {
  const ConditionAssessment(this.status, this.notes, this.incomplete);
  final RunningSuitability status;
  final List<String> notes;
  final bool incomplete;
  String get label => switch (status) {
    RunningSuitability.good => '러닝 조건 양호',
    RunningSuitability.caution => '러닝 시 주의',
    RunningSuitability.avoid => '야외 러닝 자제',
    RunningSuitability.unknown => '조건 판단 불가',
  };
}

DateTime? _time(dynamic value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
double? _number(dynamic value, double min, double max) =>
    value is num && value.isFinite && value >= min && value <= max
    ? value.toDouble()
    : null;
int? _integer(dynamic value, double min, double max) {
  final number = _number(value, min, max);
  return number != null && number == number.roundToDouble()
      ? number.toInt()
      : null;
}
