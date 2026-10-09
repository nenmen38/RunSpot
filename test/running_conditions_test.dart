import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_conditions/conditions_controller.dart';
import 'package:runquest/features/run_conditions/data/conditions_service.dart';
import 'package:runquest/features/run_conditions/models/running_conditions.dart';
import 'package:runquest/features/run_conditions/widgets/conditions_panel.dart';

import 'support/live_map_fakes.dart';
import 'support/conditions_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 9, 12);
  test('관측 농도의 공식 구간 경계값을 적용합니다', () {
    for (final pair in [
      (30.0, 1),
      (31.0, 2),
      (80.0, 2),
      (81.0, 3),
      (150.0, 3),
      (151.0, 4),
    ]) {
      expect(DustObservation.grade(pair.$1, fine: false), pair.$2);
    }
    for (final pair in [
      (15.0, 1),
      (16.0, 2),
      (35.0, 2),
      (36.0, 3),
      (75.0, 3),
      (76.0, 4),
    ]) {
      expect(DustObservation.grade(pair.$1, fine: true), pair.$2);
    }
    expect(DustObservation.grade(null, fine: true), isNull);
  });
  test('양호한 두 기관 관측값이 모두 있어야 양호로 표시합니다', () {
    expect(fixture(now).assess(now).status, RunningSuitability.good);
    expect(
      fixture(now, pm25: null).assess(now).status,
      RunningSuitability.unknown,
    );
    expect(
      fixture(now, age: const Duration(hours: 3)).assess(now).status,
      RunningSuitability.unknown,
    );
    expect(
      fixture(now, age: const Duration(minutes: -16)).assess(now).status,
      RunningSuitability.unknown,
    );
    expect(
      RunningConditions(fetchedAt: now).assess(now).status,
      RunningSuitability.unknown,
    );
  });
  test('강수·기온·바람과 더 나쁜 미세먼지 농도를 반영합니다', () {
    expect(
      fixture(now, precipitation: 3).assess(now).status,
      RunningSuitability.caution,
    );
    expect(
      fixture(now, temp: 30).assess(now).status,
      RunningSuitability.caution,
    );
    expect(
      fixture(now, temp: 0).assess(now).status,
      RunningSuitability.caution,
    );
    expect(
      fixture(now, wind: 8).assess(now).status,
      RunningSuitability.caution,
    );
    expect(
      fixture(now, pm10: 81).assess(now).status,
      RunningSuitability.caution,
    );
    expect(fixture(now, pm25: 76).assess(now).status, RunningSuitability.avoid);
    expect(
      fixture(now, pm10: 151, pm25: null).assess(now).status,
      RunningSuitability.avoid,
    );
  });
  test('마지막 관측값이 정상이어도 갱신 실패 시 양호로 판단하지 않습니다', () {
    final good = fixture(now);
    for (final code in [
      'quota_exhausted',
      'refresh_in_progress',
      'provider_unavailable',
    ]) {
      final data = RunningConditions(
        fetchedAt: now,
        weather: good.weather,
        dust: good.dust,
        weatherError: code,
      );
      expect(data.assess(now).status, RunningSuitability.unknown);
      expect(data.assess(now).incomplete, isTrue);
      expect(data.refreshNotice, isNotNull);
    }
    final hazardous = fixture(now, pm25: 76);
    final data = RunningConditions(
      fetchedAt: now,
      weather: hazardous.weather,
      dust: hazardous.dust,
      weatherError: 'quota_exhausted',
    );
    expect(data.assess(now).status, RunningSuitability.avoid);
    expect(data.assess(now).incomplete, isTrue);
  });
  test('서버 갱신과 원래 관측 시각을 구분하여 해석합니다', () {
    final cached = now.subtract(const Duration(minutes: 5));
    final observed = now.subtract(const Duration(hours: 3));
    final data = RunningConditions.fromJson({
      'fetchedAt': now.toIso8601String(),
      'weather': {
        'observedAt': observed.toIso8601String(),
        'cachedAt': cached.toIso8601String(),
        'temperature': 20,
        'wind': 1,
        'rain': 0,
        'precipitation': 0,
      },
      'dust': {
        'observedAt': observed.toIso8601String(),
        'cachedAt': cached.toIso8601String(),
        'station': '중구',
        'distanceKm': 1,
        'pm10': 10,
        'pm25': 5,
      },
    });
    expect(data.weather!.cachedAt, cached);
    expect(data.dust!.cachedAt, cached);
    expect(data.assess(now).status, RunningSuitability.unknown);
  });
  test('한도 도달 시 이전 자료가 없으면 저장 자료 없음으로 표시합니다', () {
    final data = RunningConditions(
      fetchedAt: now,
      weatherError: 'quota_exhausted',
      dustError: 'quota_exhausted',
    );
    expect(data.refreshNotice, '조회 한도에 도달했습니다. 저장된 관측 자료가 없습니다.');
    expect(data.assess(now).status, RunningSuitability.unknown);
  });
  testWidgets('작은 화면에서도 호출 한도와 마지막 관측 시각을 표시합니다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ConditionsController(
      FakeConditionsService(),
      clock: () => now,
    );
    addTearDown(controller.dispose);
    final good = fixture(now);
    controller.data = RunningConditions(
      fetchedAt: now,
      weather: good.weather,
      dust: good.dust,
      dustError: 'quota_exhausted',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConditionsPanel(controller: controller)),
      ),
    );
    expect(find.text('조건 판단 불가'), findsOneWidget);
    expect(find.text('조회 한도에 도달했습니다. 마지막 관측 자료입니다.'), findsOneWidget);
    expect(find.textContaining('관측'), findsWidgets);
    await tester.tap(find.byTooltip('러닝 환경 상세'));
    await tester.pumpAndSettle();
    expect(find.text('공동 조회 한도에 도달하여 마지막 관측 자료를 표시합니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('잘못된 자료와 결측값을 0으로 바꾸지 않습니다', () {
    final result = RunningConditions.fromJson({
      'fetchedAt': now.toIso8601String(),
      'weather': {
        'temperature': '20',
        'rain': -1,
        'wind': double.nan,
        'precipitation': 1.5,
      },
      'dust': {'pm10': '-', 'pm25': -1},
    });
    expect(result.weather!.temperature, isNull);
    expect(result.weather!.rain, isNull);
    expect(result.weather!.wind, isNull);
    expect(result.weather!.precipitation, isNull);
    expect(result.dust!.pm10, isNull);
    expect(result.assess(now).status, RunningSuitability.unknown);
  });
  test('같은 위치의 반복 알림으로 중복 조회하지 않습니다', () async {
    final service = FakeConditionsService();
    final controller = ConditionsController(service);
    addTearDown(controller.dispose);
    controller.setActive(true);
    controller.setLocation(testFix());
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 10; i++) {
      controller.setLocation(testFix());
    }
    expect(service.calls, 1);
    expect(controller.data, isNotNull);
  });
  test('이동과 화면 비활성화 이후 도착한 응답을 폐기합니다', () async {
    final service = FakeConditionsService()
      ..pending = Completer<RunningConditions>();
    final controller = ConditionsController(service);
    addTearDown(controller.dispose);
    controller.setActive(true);
    controller.setLocation(testFix());
    controller.setLocation(testFix(latitude: 37.6));
    service.pending!.complete(fixture(DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    expect(controller.data, isNull);
    expect(controller.loading, isFalse);
    controller.setActive(false);
    await controller.refresh();
    expect(service.calls, 1);
  });
  test('조회 실패와 위치 권한 부재를 명확히 표시합니다', () async {
    final service = FakeConditionsService()
      ..failure = const ConditionsFailure('unsupported_area');
    final controller = ConditionsController(service);
    addTearDown(controller.dispose);
    controller.setActive(true);
    controller.setLocation(testFix());
    await Future<void>.delayed(Duration.zero);
    expect(controller.error, contains('지원하지 않습니다'));
    controller.setLocation(null);
    expect(controller.data, isNull);
    expect(controller.error, contains('현재 위치'));
  });
  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('러닝 환경과 상세가 ${size.width} 너비에 맞습니다', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ConditionsController(FakeConditionsService())
        ..data = fixture(DateTime.now());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(children: [ConditionsPanel(controller: controller)]),
          ),
        ),
      );
      expect(find.text('러닝 조건 양호'), findsOneWidget);
      await tester.tap(find.byTooltip('러닝 환경 상세'));
      await tester.pumpAndSettle();
      expect(find.text('미세먼지'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
