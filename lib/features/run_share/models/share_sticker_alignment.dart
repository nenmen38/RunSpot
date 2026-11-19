/// 움직이는 스티커의 중심과 가장 가까우며 캔버스 안에 들어가는 정렬선을 찾습니다.
double? nearestStickerGuide(
  double center,
  Iterable<double> guides, {
  required double minCenter,
  required double maxCenter,
  required double tolerance,
}) {
  double? nearest;
  var nearestDistance = tolerance;
  for (final guide in guides) {
    if (guide < minCenter || guide > maxCenter) continue;
    final distance = (guide - center).abs();
    if (distance > nearestDistance ||
        (distance == nearestDistance && nearest != null)) {
      continue;
    }
    nearest = guide;
    nearestDistance = distance;
  }
  return nearest;
}
