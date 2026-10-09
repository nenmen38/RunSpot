import 'package:latlong2/latlong.dart';

class RunRoute {
  const RunRoute.empty() : segments = const [];

  RunRoute(Iterable<Iterable<LatLng>> source)
    : segments = List.unmodifiable(
        source.map((segment) => List<LatLng>.unmodifiable(segment)),
      ) {
    for (final segment in segments) {
      if (segment.isEmpty) throw const FormatException('빈 경로 구간입니다.');
      for (final point in segment) {
        if (!point.latitude.isFinite ||
            !point.longitude.isFinite ||
            point.latitude.abs() > 90 ||
            point.longitude.abs() > 180) {
          throw const FormatException('경로 좌표가 올바르지 않습니다.');
        }
      }
    }
  }

  final List<List<LatLng>> segments;
  bool get isEmpty => segments.isEmpty;

  // 일시정지와 위치 단절 구간을 유지하며 좌표 이외의 위치 정보는 보관하지 않습니다.
  List<List<List<double>>> toJson() => segments
      .map(
        (segment) =>
            segment.map((point) => [point.latitude, point.longitude]).toList(),
      )
      .toList();

  factory RunRoute.fromJson(Object? value) {
    if (value is! List) {
      throw const FormatException('경로 구간이 올바르지 않습니다.');
    }
    return RunRoute(
      value.map((segment) {
        if (segment is! List || segment.isEmpty) {
          throw const FormatException('경로 구간이 올바르지 않습니다.');
        }
        return segment.map((point) {
          if (point is! List ||
              point.length != 2 ||
              point[0] is! num ||
              point[1] is! num) {
            throw const FormatException('경로 좌표가 올바르지 않습니다.');
          }
          return LatLng(
            (point[0] as num).toDouble(),
            (point[1] as num).toDouble(),
          );
        });
      }),
    );
  }
}
