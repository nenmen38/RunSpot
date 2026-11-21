import 'dart:ui';

import 'package:latlong2/latlong.dart';

import 'run_route.dart';
import 'run_split.dart';

/// 지도에 그릴 경로 한 조각과 그 색입니다.
class PaceRoutePiece {
  const PaceRoutePiece(this.points, this.color);
  final List<LatLng> points;
  final Color color;
}

const paceFast = Color(0xFF16A34A);
const paceSlow = Color(0xFFDC2626);
const paceDefault = Color(0xFF16836F);

/// 이번 러닝에서 빠른 구간부터 느린 구간까지의 색입니다.
const paceBands = [
  (label: '매우 빠름', color: paceFast),
  (label: '빠름', color: Color(0xFF84A818)),
  (label: '보통', color: Color(0xFFF59E0B)),
  (label: '느림', color: Color(0xFFEA580C)),
  (label: '매우 느림', color: paceSlow),
];

/// 1km 구간 기록으로 경로를 구간별 색으로 나눕니다.
/// 경로를 따라 거리를 재며 몇 번째 km인지 정하고, 그 구간 페이스가 이번 러닝에서
/// 빠른 편일수록 초록, 느린 편일수록 빨강으로 칠합니다. 구간이 하나뿐이면 기본색 한 가지입니다.
List<PaceRoutePiece> paceColoredRoute(RunRoute route, List<RunSplit>? splits) {
  final paces = [
    for (final split in splits ?? const <RunSplit>[])
      split.pace?.inMicroseconds,
  ];
  final measured = paces.whereType<int>();
  if (measured.length < 2) {
    return [
      for (final segment in route.segments)
        PaceRoutePiece(segment, paceDefault),
    ];
  }
  final fastest = measured.reduce((a, b) => a < b ? a : b);
  final slowest = measured.reduce((a, b) => a > b ? a : b);
  Color colorOf(int index) {
    final pace = paces[index];
    if (pace == null || slowest == fastest) return paceDefault;
    final fraction = (pace - fastest) / (slowest - fastest);
    return paceBands[(fraction * (paceBands.length - 1)).round()].color;
  }

  const distance = Distance();
  final pieces = <PaceRoutePiece>[];
  var travelled = 0.0;
  for (final segment in route.segments) {
    if (segment.isEmpty) continue;
    var index = (travelled ~/ 1000).clamp(0, paces.length - 1);
    var current = <LatLng>[segment.first];
    for (var i = 1; i < segment.length; i++) {
      travelled += distance(segment[i - 1], segment[i]);
      current.add(segment[i]);
      final next = (travelled ~/ 1000).clamp(0, paces.length - 1);
      if (next != index) {
        pieces.add(PaceRoutePiece(current, colorOf(index)));
        // 다음 조각은 지금 점에서 이어 그려 선이 끊기지 않게 합니다.
        current = [segment[i]];
        index = next;
      }
    }
    if (current.length > 1 || pieces.isEmpty) {
      pieces.add(PaceRoutePiece(current, colorOf(index)));
    }
  }
  return pieces;
}

/// 지도에 보낼 색 문자열(#RRGGBB)입니다.
String paceColorHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
