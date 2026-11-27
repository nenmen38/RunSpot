import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_share/models/share_route.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';
import 'package:runquest/features/settings/location_privacy.dart';

class _MemoryStore implements AppearanceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// 위도 0.0002도(약 22m)씩 북쪽으로 가는 [count]개 점의 한 구간 경로입니다.
RunRoute line(int count) =>
    RunRoute([List.generate(count, (i) => LatLng(37.5 + i * 0.0002, 127))]);

int pointCount(ShareRoute route) =>
    route.segments.fold(0, (sum, segment) => sum + segment.length);

void main() {
  test('공유 카드 경로는 출발·도착 주변 반경 안의 점을 잘라 냅니다', () {
    final full = ShareRoute.shape(line(120));
    expect(pointCount(full), 120);
    final hidden = ShareRoute.shape(line(120), hideMeters: 300);
    // 22m 간격이라 양 끝에서 14개(300m)씩 빠집니다.
    expect(pointCount(hidden), lessThan(120 - 24));
    expect(pointCount(hidden), greaterThan(120 - 34));
    expect(hidden.isEmpty, isFalse);
  });

  test('경로가 너무 짧으면 가리고 나서 비어 경로 없이 만들어집니다', () {
    expect(ShareRoute.shape(line(20), hideMeters: 300).isEmpty, isTrue);
    expect(ShareRoute.shape(line(20)).isEmpty, isFalse);
  });

  test('경로 중간에 시작 지점을 다시 지나면 그 구간도 가리고 선으로 잇지 않습니다', () {
    // 북쪽으로 갔다가 같은 길로 돌아오는 왕복 경로입니다.
    final out = List.generate(100, (i) => LatLng(37.5 + i * 0.0002, 127));
    final back = out.reversed.toList();
    final route = RunRoute([out, back]);
    final hidden = ShareRoute.shape(route, hideMeters: 300);
    for (final segment in hidden.segments) {
      expect(segment.length, greaterThan(1));
    }
    expect(pointCount(hidden), lessThan(200 - 24));
  });

  test('보호 반경은 기본 300m이고 저장해 다시 불러옵니다', () async {
    final store = _MemoryStore();
    final first = LocationPrivacy(store: store);
    expect(first.radiusMeters, 300);
    expect(first.enabled, isTrue);
    expect(first.summary, '반경 300m 가림');
    await first.setRadius(500);
    await first.setRadius(123); // 고를 수 없는 값은 무시합니다.
    final second = LocationPrivacy(store: store);
    await second.load();
    expect(second.radiusMeters, 500);
    await second.setRadius(0);
    expect(second.enabled, isFalse);
    expect(second.summary, '끔');
  });

  testWidgets('설정 화면에서 반경을 고르면 바로 바뀝니다', (tester) async {
    final privacy = LocationPrivacy(store: _MemoryStore());
    await tester.pumpWidget(
      MaterialApp(home: LocationPrivacyScreen(privacy: privacy)),
    );
    expect(find.text('실시간 위치 공유'), findsOneWidget);
    await tester.tap(find.text('200m'));
    await tester.pumpAndSettle();
    expect(privacy.radiusMeters, 200);
    await tester.tap(find.text('끄기'));
    await tester.pumpAndSettle();
    expect(privacy.radiusMeters, 0);
    expect(find.textContaining('지금은 꺼져 있어요'), findsOneWidget);
  });
}
