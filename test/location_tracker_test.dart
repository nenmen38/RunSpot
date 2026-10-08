import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/data/location_service.dart';
import 'package:runquest/features/home/data/location_tracker.dart';
import 'package:runquest/features/home/models/live_runner.dart';

import 'support/live_map_fakes.dart';

void main() {
  late FakeLocationService service;
  late LocationTracker tracker;
  late List<LocationFix> fixes;
  late List<LocationFailure> failures;

  setUp(() {
    service = FakeLocationService();
    fixes = [];
    failures = [];
    tracker = LocationTracker(
      service,
      onFix: fixes.add,
      onFailure: failures.add,
    );
  });
  tearDown(() async {
    await tracker.close();
    await service.updates.close();
  });

  test('같은 모드 갱신은 네이티브 구독을 다시 시작하지 않습니다', () async {
    await tracker.setMode(LocationTrackingMode.recording, waitForFix: true);
    await tracker.setMode(LocationTrackingMode.recording);
    expect(service.watchModes, [true]);
    expect(service.activeWatches, 1);
  });

  test('기존 구독 해제가 끝난 뒤에만 실행 모드를 교체합니다', () async {
    await tracker.setMode(LocationTrackingMode.map);
    service.pendingCancellation = Completer<void>();
    final change = tracker.setMode(LocationTrackingMode.recording);
    await Future<void>.delayed(Duration.zero);
    expect(service.watchModes, [false]);
    expect(service.activeWatches, 1);
    service.pendingCancellation!.complete();
    await change;
    expect(service.watchModes, [false, true]);
    expect(service.activeWatches, 1);
  });

  test('닫는 동안 대기 중인 구독 교체는 새 측정을 만들지 않습니다', () async {
    await tracker.setMode(LocationTrackingMode.map);
    service.pendingCancellation = Completer<void>();
    final change = tracker.setMode(LocationTrackingMode.recording);
    await Future<void>.delayed(Duration.zero);
    final closing = tracker.close();
    service.pendingCancellation!.complete();
    await change;
    await closing;
    expect(service.watchModes, [false]);
    expect(service.activeWatches, 0);
    await tracker.setMode(LocationTrackingMode.recording);
    expect(service.watchModes, [false]);
  });

  test('시작 준비 중 해제하면 첫 위치 대기를 즉시 취소합니다', () async {
    service.emitInitialFix = false;
    final ready = tracker.setMode(
      LocationTrackingMode.recording,
      waitForFix: true,
    );
    await Future<void>.delayed(Duration.zero);
    await tracker.setMode(LocationTrackingMode.stopped);
    expect(await ready, isNull);
    expect(service.activeWatches, 0);
  });

  test('스트림 종료와 오류는 준비 대기를 해제하고 실패를 알립니다', () async {
    service.emitInitialFix = false;
    final ready = tracker.setMode(
      LocationTrackingMode.recording,
      waitForFix: true,
    );
    await Future<void>.delayed(Duration.zero);
    service.updates.addError(const LocationFailure(LocationProblem.denied));
    expect(await ready, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(failures.single.problem, LocationProblem.denied);
    expect(service.activeWatches, 0);
    await tracker.setMode(LocationTrackingMode.recording);
    await service.updates.close();
    await Future<void>.delayed(Duration.zero);
    expect(failures.last.problem, LocationProblem.unavailable);
    expect(service.activeWatches, 0);
  });
}
