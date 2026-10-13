class RunTemperature {
  RunTemperature({required this.celsius, required DateTime observedAt})
    : observedAt = observedAt.toUtc() {
    if (!celsius.isFinite || celsius < -80 || celsius > 60) {
      throw const FormatException('기온 자료가 올바르지 않습니다.');
    }
  }

  final double celsius;
  final DateTime observedAt;

  bool isFreshAt(DateTime endedAt) =>
      endedAt.difference(observedAt) <= const Duration(hours: 2) &&
      observedAt.difference(endedAt) <= const Duration(minutes: 15);

  String get label => '${celsius.toStringAsFixed(1)} °C';

  Map<String, Object> toJson() => {
    'temperature_c': celsius,
    'temperature_observed_at': observedAt.toIso8601String(),
  };

  static RunTemperature? fromJson(Map<String, dynamic> row) {
    final value = row['temperature_c'];
    final time = row['temperature_observed_at'];
    if (value == null && time == null) return null;
    if (value is! num || time is! String) {
      throw const FormatException('기온 자료가 올바르지 않습니다.');
    }
    return RunTemperature(
      celsius: value.toDouble(),
      observedAt: DateTime.parse(time),
    );
  }
}
