import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:runquest/features/health/data/run_health_service.dart';
import 'package:runquest/features/health/models/run_health_data.dart';
import 'package:runquest/features/health/widgets/run_health_panel.dart';

final start = DateTime.utc(2026, 10, 26, 1);
final end = start.add(const Duration(minutes: 10));
HealthDataPoint point(
  String id,
  double value, {
  String source = 'watch',
  HealthDataType type = HealthDataType.HEART_RATE,
  int from = 1,
  int to = 1,
  RecordingMethod method = RecordingMethod.automatic,
}) => HealthDataPoint(
  uuid: id,
  value: NumericHealthValue(numericValue: value),
  type: type,
  unit: type == HealthDataType.HEART_RATE
      ? HealthDataUnit.BEATS_PER_MINUTE
      : HealthDataUnit.KILOCALORIE,
  dateFrom: start.add(Duration(minutes: from)),
  dateTo: start.add(Duration(minutes: to)),
  sourcePlatform: HealthPlatformType.appleHealth,
  sourceDeviceId: source,
  sourceId: source,
  sourceName: source,
  recordingMethod: method,
);

class FakeHealth extends Health {
  List<HealthDataAccess>? requested;
  final reads = <HealthDataType>[];
  VoidCallback? afterRead;
  final permitted = <HealthDataType>{HealthDataType.HEART_RATE};
  @override
  Future<void> configure() async {}
  @override
  Future<HealthConnectSdkStatus?> getHealthConnectSdkStatus() async =>
      HealthConnectSdkStatus.sdkAvailable;
  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requested = permissions;
    return true;
  }

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => types.every(permitted.contains);
  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    reads.addAll(types);
    afterRead?.call();
    expect(startTime, start);
    expect(endTime, end);
    return [point('heart', 140)];
  }
}

class FakeService implements RunHealthService {
  int requests = 0, reads = 0;
  Completer<RunHealthData>? pending;
  RunHealthData? result;
  @override
  Future<void> requestAccess() async {
    requests++;
  }

  @override
  Future<RunHealthData> read(
    DateTime start,
    DateTime end, {
    bool Function()? canRead,
  }) async {
    reads++;
    return pending == null
        ? result ?? summarizeRunHealth([point('a', 140)], start, end)
        : await pending!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('여러 출처는 합산하지 않고 중복 표본과 직접 입력을 제외합니다', () {
    final result = summarizeRunHealth(
      [
        point('a', 120),
        point('a', 120),
        point('b', 160, to: 2, from: 2),
        point('manual', 200, method: RecordingMethod.manual),
        point('outside', 220, from: -1, to: -1),
        point('other', 180, source: 'other'),
        point(
          'energy',
          50,
          type: HealthDataType.ACTIVE_ENERGY_BURNED,
          from: 0,
          to: 5,
        ),
        point(
          'partial',
          100,
          type: HealthDataType.ACTIVE_ENERGY_BURNED,
          from: 5,
          to: 11,
        ),
      ],
      start,
      end,
    );
    expect(result.sources.length, 2);
    final watch = result.sources.firstWhere(
      (source) => source.label == 'watch',
    );
    expect(watch.heartSamples, 2);
    expect(watch.averageHeartRate, 140);
    expect(watch.maxHeartRate, 160);
    expect(watch.activeCalories, 50);
  });
  test('겹치는 활동 칼로리는 잘못 합산하지 않습니다', () {
    final result = summarizeRunHealth(
      [
        point(
          'a',
          30,
          type: HealthDataType.ACTIVE_ENERGY_BURNED,
          from: 0,
          to: 5,
        ),
        point(
          'b',
          40,
          type: HealthDataType.ACTIVE_ENERGY_BURNED,
          from: 4,
          to: 8,
        ),
      ],
      start,
      end,
    ).sources.single;
    expect(result.activeCalories, isNull);
    expect(result.overlappingCalories, isTrue);
    expect(result.averageHeartRate, isNull);
  });
  test('읽기만 요청하고 안드로이드에서 거절한 항목은 조회하지 않습니다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final health = FakeHealth();
    final service = DeviceRunHealthService(health: health);
    await service.requestAccess();
    expect(health.requested, [HealthDataAccess.READ, HealthDataAccess.READ]);
    final data = await service.read(start, end);
    expect(health.reads, [HealthDataType.HEART_RATE]);
    expect(data.notices.single, contains('활동 칼로리 읽기 권한'));
    expect(data.sources.single.activeCalories, isNull);
  });
  test('조회가 중단되면 다음 건강 항목의 요청을 시작하지 않습니다', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    var active = true;
    final health = FakeHealth();
    health.permitted.add(HealthDataType.ACTIVE_ENERGY_BURNED);
    health.afterRead = () => active = false;
    await DeviceRunHealthService(health: health)
        .read(start, end, canRead: () => active);
    expect(health.reads, [HealthDataType.HEART_RATE]);
  });

  testWidgets('상세 진입 시 권한 요청이나 확인창 없이 자동 조회합니다', (tester) async {
    final service = FakeService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunHealthPanel(
            service: service,
            start: start,
            end: end,
            isCurrentOwner: () => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.reads, 1);
    expect(service.requests, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('140 회/분'), findsNWidgets(2));
    expect(find.text('--'), findsOneWidget);
    expect(find.text('불러오기'), findsNothing);
  });

  testWidgets('선택 기기를 전달하고 백그라운드와 화면 종료 시 참조를 비웁니다', (tester) async {
    final service = FakeService()
      ..result = summarizeRunHealth(
        [
          point('a', 140, source: 'a-watch'),
          point('b', 160, source: 'b-watch'),
        ],
        start,
        end,
      );
    RunHealthSource? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunHealthPanel(
            service: service,
            start: start,
            end: end,
            isCurrentOwner: () => true,
            onSelectedSourceChanged: (source) => selected = source,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected?.averageHeartRate, 140);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2. b-watch').last);
    await tester.pumpAndSettle();
    expect(selected?.averageHeartRate, 160);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(selected, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(selected?.averageHeartRate, 140);
    await tester.pumpWidget(const SizedBox());
    expect(selected, isNull);
  });

  testWidgets('자료가 없으면 수치를 추정하지 않고 빈 값으로 표시합니다', (tester) async {
    final service = FakeService()..result = summarizeRunHealth([], start, end);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunHealthPanel(
            service: service,
            start: start,
            end: end,
            isCurrentOwner: () => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('--'), findsNWidgets(3));
    expect(find.textContaining('권한과 동기화'), findsNothing);
    await tester.tap(find.byTooltip('건강 데이터 새로고침'));
    await tester.pumpAndSettle();
    expect(service.reads, 2);
  });

  testWidgets('조회 중 계정 변경과 백그라운드 전환 후 늦은 건강 자료를 폐기합니다', (tester) async {
    var owner = true;
    final service = FakeService()..pending = Completer<RunHealthData>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunHealthPanel(
            service: service,
            start: start,
            end: end,
            isCurrentOwner: () => owner,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(service.reads, 1);
    owner = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    service.pending!.complete(
      summarizeRunHealth([point('a', 140)], start, end),
    );
    await tester.pumpAndSettle();
    expect(find.text('평균 심박'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
}
