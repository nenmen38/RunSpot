import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/data/location_service.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';

void main() {
  late FakeLocationService location;
  late FakeRunnerService service;
  late LiveMapController controller;
  late FakeRunRecordService historyService;
  late RunHistoryController history;
  late FakeRunOutbox outbox;

  setUp(() {
    location = FakeLocationService();
    service = FakeRunnerService();
    historyService = FakeRunRecordService();
    outbox = FakeRunOutbox();
    history = RunHistoryController(historyService, outbox: outbox);
    controller = LiveMapController(
      locationService: location,
      runnerService: service,
      runHistory: history,
    );
  });
  tearDown(() async {
    controller.dispose();
    history.dispose();
    await location.updates.close();
  });

  test('현재 위치는 기본적으로 서버에 전송하지 않습니다', () async {
    await controller.start();
    expect(controller.position, isNotNull);
    expect(controller.sharing, isFalse);
    expect(service.actions, isEmpty);
    location.updates.add(testFix(latitude: 37.567));
    await Future<void>.delayed(Duration.zero);
    expect(controller.position!.latitude, 37.567);
    expect(service.actions, isEmpty);
  });

  test('러닝 시작 전에는 위치가 있어도 공유와 주변 조회를 허용하지 않습니다', () async {
    await controller.start();
    expect(controller.position, isNotNull);
    expect(controller.canShareLocation, isFalse);
    await controller.setSharing(true);
    await controller.refresh();
    expect(controller.sharing, isFalse);
    expect(service.actions, isEmpty);
    expect(service.lastRadius, isNull);
    expect(service.onChanged, isNull);
  });

  test('일시 정지 시 공유를 중단하고 러닝을 계속해도 자동 공개하지 않습니다', () async {
    await controller.startRun();
    expect(controller.canShareLocation, isTrue);
    await controller.setSharing(true);
    controller.pauseRun();
    expect(controller.sharing, isFalse);
    expect(controller.canShareLocation, isFalse);
    await Future<void>.delayed(Duration.zero);
    await controller.setSharing(true);
    location.updates.add(testFix(latitude: 37.568));
    await Future<void>.delayed(Duration.zero);
    expect(service.actions, ['publish', 'stop']);
    expect(controller.runners, isEmpty);
    await controller.startRun();
    expect(controller.canShareLocation, isTrue);
    expect(controller.sharing, isFalse);
    expect(service.actions, ['publish', 'stop']);
    await controller.setSharing(true);
    expect(controller.sharing, isTrue);
    expect(service.actions, ['publish', 'stop', 'publish']);
  });

  test('공유 준비 중 일시 정지하면 위치를 전송하지 않습니다', () async {
    await controller.startRun();
    service.pendingDisconnect = Completer<void>();
    final sharing = controller.setSharing(true);
    await Future<void>.delayed(Duration.zero);
    controller.pauseRun();
    service.pendingDisconnect!.complete();
    await sharing;
    await Future<void>.delayed(Duration.zero);
    expect(service.actions, ['stop']);
    expect(controller.sharing, isFalse);
    expect(controller.changingSharing, isFalse);
    expect(service.onChanged, isNull);
  });

  for (final finish in [false, true]) {
    test('위치 전송 중 ${finish ? '종료' : '일시 정지'}하면 마지막 서버 작업은 삭제입니다', () async {
      await controller.startRun();
      service.pendingPublish = Completer<void>();
      final sharing = controller.setSharing(true);
      await Future<void>.delayed(Duration.zero);
      Future<RunSummary?>? ending;
      if (finish) {
        ending = controller.finishRun();
      } else {
        controller.pauseRun();
      }
      expect(controller.sharing, isFalse);
      service.pendingPublish!.complete();
      await sharing;
      await ending;
      await Future<void>.delayed(Duration.zero);
      expect(service.actions, ['publish', 'stop']);
      expect(controller.sharing, isFalse);
      expect(controller.changingSharing, isFalse);
      expect(service.onChanged, isNull);
      await controller.setSharing(true);
      expect(service.actions, ['publish', 'stop']);
    });
  }

  test('러닝 시작은 위치를 공개하지 않고 종료 후 새 측정을 시작합니다', () async {
    await controller.startRun();
    expect(controller.runSession!.isRunning, isTrue);
    expect(controller.sharing, isFalse);
    expect(service.actions, isEmpty);
    final session = controller.runSession;
    final summary = await controller.finishRun();
    expect(summary, isNotNull);
    expect(session!.isRunning, isFalse);
    expect(controller.runSession, isNull);
    await controller.startRun();
    expect(controller.runSession, isNot(same(session)));
    expect(controller.runSession!.distanceMeters, 0);
  });

  test('러닝 종료 시 공유도 중단합니다', () async {
    await controller.startRun();
    await controller.setSharing(true);
    await controller.finishRun();
    expect(controller.sharing, isFalse);
    expect(controller.runSession, isNull);
    expect(service.actions, ['publish', 'stop']);
    expect(historyService.records, hasLength(1));
  });

  test('서버 저장 실패 시 기기에 보관하고 다음 러닝을 시작할 수 있습니다', () async {
    await controller.startRun();
    historyService.saveFailure = StateError('연결 실패');
    final result = await controller.finishRun();
    expect(result, isNotNull);
    expect(controller.runSession, isNull);
    expect(controller.runError, isNull);
    final summary = historyService.attempts.single;
    expect(outbox.rows.values.single, same(summary));
    expect(history.isPending(summary.clientRunId), isTrue);
    await controller.startRun();
    expect(controller.runSession!.isRunning, isTrue);
    historyService.saveFailure = null;
    await history.syncPending();
    expect(historyService.attempts.last, same(summary));
    expect(historyService.records, hasLength(1));
    expect(outbox.rows, isEmpty);
  });

  test('기기 저장 실패 시 종료 결과를 유지하고 서버에 보내지 않습니다', () async {
    await controller.startRun();
    outbox.putFailure = StateError('저장 공간 부족');
    expect(await controller.finishRun(), isNull);
    expect(controller.runSession!.isFinished, isTrue);
    expect(controller.runError, isNotNull);
    expect(historyService.attempts, isEmpty);
    final summary = controller.runSession!.finish();
    await controller.startRun();
    expect(controller.runSession!.isFinished, isTrue);
    outbox.putFailure = null;
    expect(await controller.finishRun(), same(summary));
    expect(historyService.records, hasLength(1));
  });

  test('저장 중에는 종료와 시작을 중복 실행하지 않습니다', () async {
    await controller.startRun();
    historyService.pendingSave = Completer<void>();
    final finish = controller.finishRun();
    expect(controller.savingRun, isTrue);
    expect(await controller.finishRun(), isNull);
    await controller.startRun();
    await Future<void>.delayed(Duration.zero);
    expect(historyService.attempts, hasLength(1));
    historyService.pendingSave!.complete();
    await finish;
    expect(historyService.records, hasLength(1));
    expect(controller.savingRun, isFalse);
  });

  test('백그라운드에서도 같은 러닝의 시간과 거리를 계속 측정합니다', () async {
    location.fix = testFix(
      recordedAt: DateTime.now().subtract(const Duration(seconds: 8)),
    );
    await controller.startRun();
    final session = controller.runSession;
    final duration = session!.duration;
    final modes = List<bool>.of(location.watchModes);
    await controller.setActive(false);
    expect(session.isRunning, isTrue);
    location.updates.add(testFix(latitude: 37.567));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(session.duration, greaterThan(duration));
    expect(session.distanceMeters, greaterThan(40));
    await controller.setActive(true);
    expect(controller.runSession, same(session));
    expect(session.isRunning, isTrue);
    expect(location.watchModes, modes);
    expect(service.actions, isEmpty);
  });

  test('러닝 중 백그라운드에서는 GPS를 유지하지만 공유는 중단합니다', () async {
    location.fix = testFix(
      recordedAt: DateTime.now().subtract(const Duration(seconds: 8)),
    );
    await controller.startRun();
    await controller.setSharing(true);
    await controller.setActive(false);
    expect(controller.sharing, isFalse);
    expect(location.activeWatches, 1);
    location.updates.add(testFix(latitude: 37.568));
    await Future<void>.delayed(Duration.zero);
    expect(controller.runSession!.distanceMeters, greaterThan(100));
    expect(service.actions, ['publish', 'stop']);
    await controller.setActive(true);
    expect(controller.sharing, isFalse);
    expect(service.actions, ['publish', 'stop']);
  });

  test('일시 정지와 종료는 백그라운드 실행 설정을 해제합니다', () async {
    await controller.startRun();
    expect(location.watchModes.last, isTrue);
    controller.pauseRun();
    await Future<void>.delayed(Duration.zero);
    expect(location.watchModes.last, isFalse);
    await controller.setActive(false);
    expect(location.activeWatches, 0);
    await controller.setActive(true);
    await controller.startRun();
    expect(location.watchModes.last, isTrue);
    await controller.finishRun();
    expect(location.watchModes.last, isFalse);
  });

  test('백그라운드에서 종료하면 GPS를 완전히 해제합니다', () async {
    await controller.startRun();
    await controller.setActive(false);
    await controller.finishRun();
    await Future<void>.delayed(Duration.zero);
    expect(location.activeWatches, 0);
    expect(controller.runSession, isNull);
  });

  test('백그라운드 GPS 오류도 러닝을 정지하고 구독을 해제합니다', () async {
    await controller.startRun();
    await controller.setActive(false);
    location.updates.addError(StateError('위치 중단'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.runSession!.isRunning, isFalse);
    expect(controller.locationFailure, isNotNull);
    expect(location.activeWatches, 0);
    await controller.setActive(true);
    expect(controller.runSession!.isRunning, isFalse);
    expect(location.watchModes.last, isFalse);
  });

  test('네이티브 GPS가 응답하기 전에는 러닝을 시작하지 않습니다', () async {
    location.emitInitialFix = false;
    final start = controller.startRun();
    await Future<void>.delayed(Duration.zero);
    expect(controller.startingRun, isTrue);
    expect(controller.runSession, isNull);
    location.updates.add(testFix());
    await start;
    expect(controller.runSession!.isRunning, isTrue);
  });

  test('GPS 준비 중 백그라운드로 가면 러닝 시작을 취소합니다', () async {
    location.emitInitialFix = false;
    final start = controller.startRun();
    await Future<void>.delayed(Duration.zero);
    await controller.setActive(false);
    await start;
    expect(controller.startingRun, isFalse);
    expect(controller.runSession, isNull);
    expect(location.activeWatches, 0);
  });

  test('네이티브 측정 시작 실패를 성공으로 표시하지 않습니다', () async {
    location.watchFailure = StateError('서비스 시작 실패');
    await controller.startRun();
    expect(controller.runSession, isNull);
    expect(controller.runError, isNotNull);
    expect(location.activeWatches, 0);
  });

  test('늦은 지도 구독 해제 중 백그라운드로 가면 측정을 시작하지 않습니다', () async {
    await controller.start();
    location.pendingCancellation = Completer<void>();
    final start = controller.startRun();
    await Future<void>.delayed(Duration.zero);
    final background = controller.setActive(false);
    location.pendingCancellation!.complete();
    await start;
    await background;
    expect(controller.runSession, isNull);
    expect(location.watchModes, [false]);
    expect(location.activeWatches, 0);
  });

  test('시작 위치 확인 중 앱을 닫았다 열어도 취소된 러닝은 시작하지 않습니다', () async {
    await controller.start();
    location.pendingCurrent = Completer<LocationFix>();
    final start = controller.startRun();
    await controller.setActive(false);
    final resume = controller.setActive(true);
    location.pendingCurrent!.complete(testFix());
    await start;
    await resume;
    expect(controller.runSession, isNull);
    expect(location.watchModes, [false, false]);
    expect(controller.startingRun, isFalse);
  });

  test('부정확한 위치 또는 권한 거부 시 러닝을 시작하지 않습니다', () async {
    location.fix = testFix(accuracy: 500);
    await controller.startRun();
    expect(controller.runSession, isNull);
    expect(controller.runError, isNotNull);
    location.failure = const LocationFailure(LocationProblem.denied);
    await controller.startRun();
    expect(controller.runSession, isNull);
    expect(controller.runError, location.failure!.message);
  });

  test('러닝 중 GPS가 중단되면 일시 정지합니다', () async {
    await controller.startRun();
    location.updates.addError(StateError('위치 중단'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.runSession!.isRunning, isFalse);
    expect(controller.locationFailure, isNotNull);
    expect(service.actions, isEmpty);
  });

  test('권한 거부를 표시하고 공유하지 않습니다', () async {
    location.failure = const LocationFailure(LocationProblem.denied);
    await controller.start();
    expect(controller.locationFailure!.problem, LocationProblem.denied);
    expect(controller.position, isNull);
    await controller.setSharing(true);
    expect(service.actions, isEmpty);
    expect(controller.sharing, isFalse);
  });

  test('정확도가 낮은 위치는 공유하지 않습니다', () async {
    location.fix = testFix(accuracy: 300);
    await controller.startRun();
    await controller.setSharing(true);
    expect(controller.sharing, isFalse);
    expect(service.actions, isEmpty);
  });

  test('공유를 켜면 주변 러너를 조회하고 끄면 삭제합니다', () async {
    service.runners = [
      LiveRunner(
        id: 'runner',
        nickname: '함께러너',
        latitude: 37.567,
        longitude: 126.978,
        distanceMeters: 55,
        updatedAt: DateTime.now(),
      ),
    ];
    await controller.startRun();
    await controller.setSharing(true);
    expect(controller.sharing, isTrue);
    expect(controller.connected, isTrue);
    expect(controller.runners.single.nickname, '함께러너');
    expect(service.lastRadius, 1000);
    await controller.setSharing(false);
    expect(controller.runners, isEmpty);
    expect(service.actions, ['publish', 'stop']);
  });

  test('전송 중 공유를 꺼도 마지막 서버 작업은 삭제입니다', () async {
    await controller.startRun();
    service.pendingPublish = Completer<void>();
    final startSharing = controller.setSharing(true);
    await Future<void>.delayed(Duration.zero);
    final stopSharing = controller.setSharing(false);
    service.pendingPublish!.complete();
    await Future.wait([startSharing, stopSharing]);
    expect(service.actions, ['publish', 'stop']);
    expect(controller.sharing, isFalse);
    expect(controller.changingSharing, isFalse);
  });

  test('백그라운드 전환 시 공유를 중단하고 복귀해도 자동 공개하지 않습니다', () async {
    await controller.startRun();
    await controller.setSharing(true);
    await controller.setActive(false);
    expect(location.activeWatches, 1);
    expect(controller.sharing, isFalse);
    expect(controller.runners, isEmpty);
    expect(service.actions.last, 'stop');
    await controller.setActive(true);
    expect(controller.position, isNotNull);
    expect(controller.sharing, isFalse);
  });

  test('공유 해제 응답이 늦어도 복귀 후의 현재 위치를 지우지 않습니다', () async {
    await controller.startRun();
    await controller.setSharing(true);
    service.pendingStop = Completer<void>();
    final background = controller.setActive(false);
    await Future<void>.delayed(Duration.zero);
    await controller.setActive(true);
    service.pendingStop!.complete();
    await background;
    expect(controller.position, isNotNull);
    expect(controller.sharing, isFalse);
    expect(location.activeWatches, 1);
  });

  test('미인증 또는 비공개 서버 거절을 우회하지 않습니다', () async {
    service.publishFailure = const PostgrestException(
      message: '이메일 인증이 필요합니다.',
      code: '42501',
    );
    await controller.startRun();
    await controller.setSharing(true);
    expect(controller.sharing, isFalse);
    expect(controller.sharingError, '이메일 인증이 필요합니다.');
    expect(service.onChanged, isNull);
  });

  test('공유 중 GPS 정확도가 나빠지면 마지막 위치를 삭제합니다', () async {
    await controller.startRun();
    await controller.setSharing(true);
    location.updates.add(testFix(accuracy: 500));
    await Future<void>.delayed(Duration.zero);
    expect(controller.sharing, isFalse);
    expect(service.actions.last, 'stop');
    expect(controller.position, isNull);
  });

  test('실시간 변경 신호로 갱신하고 연결 중단 시 이전 위치를 숨깁니다', () async {
    await controller.startRun();
    await controller.setSharing(true);
    service.runners = [
      LiveRunner(
        id: 'nearby',
        nickname: '새러너',
        latitude: 37.567,
        longitude: 126.978,
        distanceMeters: 100,
        updatedAt: DateTime.now(),
      ),
    ];
    service.onChanged!();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(controller.runners.single.nickname, '새러너');
    service.onConnection!(false);
    expect(controller.runners, isEmpty);
  });
}
