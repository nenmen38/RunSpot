import 'run_split.dart';

/// 페이스(속도)로 소모 칼로리(kcal)를 추정합니다.
///
/// 미국스포츠의학회(ACSM)의 산소 소비량 식을 씁니다.
/// - 달리기(분속 134m, 시속 약 8km 이상): 산소 소비량 = 0.2 × 분속 + 3.5 (ml/kg/분)
/// - 걷기(그보다 느림): 산소 소비량 = 0.1 × 분속 + 3.5
/// - 산소 1L ≈ 5kcal
///
/// 1km 구간 기록이 있으면 구간마다 따로 계산해 더하므로 중간에 페이스가 달라져도 반영됩니다.
/// 일시 정지한 시간은 빼고 계산합니다. 거리, 시간, 체중 중 하나라도 없으면 null입니다.
int? estimateRunCalories({
  required double distanceMeters,
  required int durationSeconds,
  List<RunSplit>? splits,
  required double? weightKg,
}) {
  if (!distanceMeters.isFinite ||
      distanceMeters <= 0 ||
      durationSeconds <= 0 ||
      weightKg == null ||
      !weightKg.isFinite ||
      weightKg <= 0) {
    return null;
  }
  final parts = [
    for (final split in splits ?? const <RunSplit>[])
      if (split.distanceMeters > 0 && split.duration.inMicroseconds > 0)
        (split.distanceMeters, split.duration.inMicroseconds / 6e7),
  ];
  if (parts.isEmpty) parts.add((distanceMeters, durationSeconds / 60));
  var kcal = 0.0;
  for (final (meters, minutes) in parts) {
    // GPS가 튄 구간이 칼로리를 부풀리지 않도록 분속은 시속 30km(500m)까지만 셉니다.
    final speed = (meters / minutes).clamp(0, 500).toDouble();
    final oxygen = speed >= 134 ? 0.2 * speed + 3.5 : 0.1 * speed + 3.5;
    kcal += oxygen * weightKg / 1000 * 5 * minutes;
  }
  return kcal.round();
}
