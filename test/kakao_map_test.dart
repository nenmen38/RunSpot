import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/shared/maps/kakao_map_config.dart';
import 'package:runquest/shared/maps/run_map.dart';

import 'support/map_fakes.dart';

void main() {
  test('지도 설정은 키 종류·HTTPS 도메인·운영 로컬 주소를 검사합니다', () {
    const valid = KakaoMapConfig(
      javaScriptKey: '0123456789abcdef0123456789abcdef',
      origin: 'https://maps.example.com',
    );
    expect(valid.validate(release: true), isNull);
    expect(
      const KakaoMapConfig(
        javaScriptKey: '',
        origin: 'https://localhost',
      ).validate(release: false),
      isNotNull,
    );
    for (final origin in [
      'http://example.com',
      'https://user:pass@example.com',
      'https://example.com/path',
      'https://example.com?x=1',
      'https://localhost',
    ]) {
      expect(
        KakaoMapConfig(
          javaScriptKey: valid.javaScriptKey,
          origin: origin,
        ).validate(release: true),
        isNotNull,
      );
    }
    expect(
      KakaoMapConfig(
        javaScriptKey: valid.javaScriptKey,
        origin: 'https://localhost',
      ).validate(release: false),
      isNull,
    );
  });

  testWidgets('준비 전에 받은 카메라 명령과 좌표를 준비 완료 뒤에 전달합니다', (tester) async {
    final controller = RunMapController();
    addTearDown(controller.dispose);
    final bridge = FakeMapBridge()..autoReady = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunMap(
            controller: controller,
            bridgeFactory: () => bridge,
            position: const LatLng(37, 127),
          ),
        ),
      ),
    );
    controller.move(const LatLng(37, 127), 16.5);
    expect(bridge.updates, isEmpty);
    bridge.emit({'type': 'ready'});
    await tester.pump();
    expect(bridge.updates.last['position'], [37, 127]);
    expect((bridge.updates.last['camera'] as Map)['zoom'], 16.5);
    await tester.pump(const Duration(seconds: 21));
    expect(find.textContaining('지연'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(bridge.disposed, isTrue);
  });

  testWidgets('오류와 지연을 재시도하고 이전 웹뷰의 늦은 응답은 무시합니다', (tester) async {
    final controller = RunMapController();
    addTearDown(controller.dispose);
    final bridges = [FakeMapBridge()..autoReady = false, FakeMapBridge()];
    var index = 0, ready = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunMap(
            controller: controller,
            bridgeFactory: () => bridges[index++],
            onReady: () => ready++,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 21));
    expect(find.textContaining('지연'), findsOneWidget);
    await tester.tap(find.text('지도 다시 불러오기'));
    await tester.pumpAndSettle();
    expect(bridges.first.disposed, isTrue);
    bridges.first.onError!('이전 오류');
    bridges.first.emit({'type': 'ready'});
    expect(ready, 1);
    expect(find.text('이전 오류'), findsNothing);
    bridges.last.onError!('연결 오류');
    await tester.pump();
    expect(find.text('연결 오류'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('서로 다른 위치 갱신은 직렬화하고 마지막 상태까지 반영합니다', (tester) async {
    final controller = RunMapController();
    addTearDown(controller.dispose);
    final pending = Completer<void>();
    final bridge = FakeMapBridge()..pendingUpdate = pending;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunMap(controller: controller, bridgeFactory: () => bridge),
        ),
      ),
    );
    await tester.pump();
    expect(bridge.updates, hasLength(1));
    controller.move(const LatLng(37, 127), 16.5);
    controller.move(const LatLng(38, 127), 17);
    expect(bridge.updates, hasLength(1));
    pending.complete();
    await tester.pumpAndSettle();
    expect(bridge.updates, hasLength(2));
    expect((bridge.updates.last['camera'] as Map)['center'], [38, 127]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('알 수 없는 러너와 잘못된 카메라 이벤트를 거절합니다', (tester) async {
    final controller = RunMapController();
    addTearDown(controller.dispose);
    final bridge = FakeMapBridge();
    final selected = <String>[];
    var gestures = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunMap(
            controller: controller,
            bridgeFactory: () => bridge,
            markers: const [
              RunMapMarker(
                id: 'friend',
                point: LatLng(37, 127),
                nickname: '<script>친구</script>',
              ),
            ],
            onMarkerTap: selected.add,
            onGesture: () => gestures++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    bridge.onMessage!('not-json');
    bridge.emit({'type': 'marker', 'id': 'stranger'});
    bridge.emit({'type': 'marker', 'id': 'friend'});
    bridge.emit({
      'type': 'camera',
      'latitude': 91,
      'longitude': 127,
      'zoom': 17,
    });
    expect(controller.camera.center.latitude, 37.5665);
    bridge.emit({
      'type': 'camera',
      'latitude': 37,
      'longitude': 127,
      'zoom': 17,
    });
    expect(controller.camera.center.latitude, 37);
    bridge.emit({'type': 'gesture'});
    expect(gestures, 1);
    expect(selected, ['friend']);
    expect(
      (bridge.updates.last['markers'] as List).single['nickname'],
      '<script>친구</script>',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
