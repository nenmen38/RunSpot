import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/features/run_history/models/pace_route.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_history/models/run_split.dart';

void main() {
  // 북쪽으로 100m씩 25개 점을 찍어 약 2.4km를 달린 경로입니다.
  final points = [
    for (var i = 0; i < 25; i++) LatLng(37.5 + i * 100 / 111195, 127),
  ];
  final route = RunRoute([points]);
  RunSplit split(double meters, int seconds) => RunSplit(
    distanceMeters: meters,
    duration: Duration(seconds: seconds),
  );

  test('1km 구간마다 페이스에 따라 빠르면 초록, 느리면 빨강으로 나눕니다', () {
    final pieces = paceColoredRoute(route, [
      split(1000, 300),
      split(1000, 360),
      split(400, 132),
    ]);
    expect(pieces, hasLength(3));
    expect(pieces.first.color, paceFast);
    expect(pieces[1].color, paceSlow);
    // 조각은 이어 그려 선이 끊기지 않습니다.
    expect(pieces[1].points.first, pieces[0].points.last);
    expect(pieces[2].points.first, pieces[1].points.last);
    expect(pieces.last.points.last, points.last);
    // 이 러닝의 가장 빠른·느린 구간 사이 페이스는 중간색 쪽입니다.
    expect(pieces[2].color, isNot(paceFast));
    expect(pieces[2].color, isNot(paceSlow));
  });

  test('구간 기록이 없거나 하나뿐이면 기본색 한 가지로 그립니다', () {
    expect(paceColoredRoute(route, null).map((piece) => piece.color).toSet(), {
      paceDefault,
    });
    expect(paceColoredRoute(route, [split(1000, 300)]).single.points, points);
    expect(paceColorHex(paceFast), '#16a34a');
  });
}
