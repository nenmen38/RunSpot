import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 지도 표시용 좌표를 정리합니다. 원래 좌표와 구간 양끝은 보존합니다.
List<LatLng> cleanDisplayRoute(List<LatLng> points) {
  if (points.length <= 2) return points;

  const metersPerDegree = 111195.0;
  const tolerance = 4.0;
  final origin = points.first;
  final longitudeScale =
      metersPerDegree * math.cos(origin.latitude * math.pi / 180);
  final meters = [
    for (final point in points)
      math.Point<double>(
        ((point.longitude - origin.longitude + 180) % 360 - 180) *
            longitudeScale,
        (point.latitude - origin.latitude) * metersPerDegree,
      ),
  ];
  final candidates = [
    for (var i = 0; i < points.length; i++)
      if (!_isolatedSpike(meters, i, tolerance)) i,
  ];

  // 같은 구간에서 직선으로 대체해도 오차가 허용 범위 이내인 점만 생략합니다.
  final keep = List<bool>.filled(points.length, false);
  keep.first = keep.last = true;
  final ranges = [(start: 0, end: candidates.length - 1)];
  while (ranges.isNotEmpty) {
    final (:start, :end) = ranges.removeLast();
    final a = meters[candidates[start]];
    final b = meters[candidates[end]];
    var maxError = tolerance;
    var split = start;
    for (var i = start + 1; i < end; i++) {
      final point = meters[candidates[i]];
      final error = _distanceToLine(point, a, b);
      if (error > maxError) {
        maxError = error;
        split = i;
      }
    }
    if (split == start) continue;
    keep[candidates[split]] = true;
    ranges.addAll([(start: start, end: split), (start: split, end: end)]);
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

bool _isolatedSpike(List<math.Point<double>> points, int i, double tolerance) {
  if (i < 2 || i + 2 >= points.length) return false;
  final before = points[i - 1];
  final after = points[i + 1];
  final direction = after - before;
  if (direction.magnitude < 8 || direction.magnitude > 35) return false;

  // 앞뒤 두 점씩 진행 방향이 일치하고 가운데 점만 옆으로 튄 경우입니다.
  final earlier = points[i - 2];
  final later = points[i + 2];
  if (earlier.distanceTo(before) > 20 || later.distanceTo(after) > 20) {
    return false;
  }
  if (_projection(earlier, before, after) >= 0 ||
      _projection(later, before, after) <= 1 ||
      _distanceToLine(before, earlier, later) > tolerance / 2 ||
      _distanceToLine(after, earlier, later) > tolerance / 2) {
    return false;
  }
  final current = points[i];
  final progress = _projection(current, before, after);
  final offset = _distanceToLine(current, before, after);
  return progress >= .2 && progress <= .8 && offset > tolerance && offset <= 18;
}

double _projection(
  math.Point<double> point,
  math.Point<double> start,
  math.Point<double> end,
) {
  final line = end - start;
  final lengthSquared = line.x * line.x + line.y * line.y;
  if (lengthSquared == 0) return 0;
  final offset = point - start;
  return (offset.x * line.x + offset.y * line.y) / lengthSquared;
}

double _distanceToLine(
  math.Point<double> point,
  math.Point<double> start,
  math.Point<double> end,
) {
  final ratio = _projection(point, start, end).clamp(0.0, 1.0).toDouble();
  return point.distanceTo(start + (end - start) * ratio);
}
