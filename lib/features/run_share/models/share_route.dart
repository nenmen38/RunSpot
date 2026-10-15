import 'dart:math' as math;
import 'dart:ui';

import 'package:latlong2/latlong.dart';

import '../../run_history/models/run_route.dart';

class ShareRoute {
  ShareRoute._(List<List<Offset>> segments)
    : segments = List.unmodifiable(segments.map(List<Offset>.unmodifiable));
  final List<List<Offset>> segments;
  bool get isEmpty => segments.isEmpty;

  factory ShareRoute.shape(RunRoute route) {
    if (route.isEmpty) return ShareRoute._([]);
    const distance = Distance();
    final safe = <List<LatLng>>[];
    for (final segment in route.segments) {
      var current = <LatLng>[];
      void finish() {
        if (current.length > 1) safe.add(current);
        current = [];
      }

      for (final point in segment) {
        // 일시 정지와 긴 위치 단절은 선으로 연결하지 않습니다.
        if (current.isNotEmpty && distance(current.last, point) > 50) finish();
        current.add(point);
      }
      finish();
    }
    if (safe.isEmpty) return ShareRoute._([]);
    final anchor = safe.first.first;
    double longitudeDelta(double value) =>
        (value - anchor.longitude + 540) % 360 - 180;
    final projected = safe
        .map(
          (segment) => segment
              .map(
                (point) => Offset(
                  longitudeDelta(point.longitude) *
                      math.cos(anchor.latitude * math.pi / 180),
                  -point.latitude,
                ),
              )
              .toList(),
        )
        .toList();
    final points = projected.expand((segment) => segment).toList();
    final minX = points.map((p) => p.dx).reduce(math.min);
    final maxX = points.map((p) => p.dx).reduce(math.max);
    final minY = points.map((p) => p.dy).reduce(math.min);
    final maxY = points.map((p) => p.dy).reduce(math.max);
    final span = math.max(maxX - minX, maxY - minY);
    if (span < 1e-9) return ShareRoute._([]);
    return ShareRoute._(
      projected
          .map(
            (segment) => segment
                .map(
                  (point) => Offset(
                    ((point.dx - (minX + maxX) / 2) / span + .5).clamp(
                      0.0,
                      1.0,
                    ),
                    ((point.dy - (minY + maxY) / 2) / span + .5).clamp(
                      0.0,
                      1.0,
                    ),
                  ),
                )
                .toList(),
          )
          .toList(),
    );
  }
}
