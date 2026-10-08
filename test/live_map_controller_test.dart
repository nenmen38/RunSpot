import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/data/location_service.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/models/live_runner.dart';
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

  setUp(() {
    location = FakeLocationService();
    service = FakeRunnerService();
    historyService = FakeRunRecordService();
    history = RunHistoryController(historyService);
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

  test('저장 실패 시 종료 결과를 유지하고 같은 식별자로 재시도합니다', () async {
    await controller.startRun();
    historyService.saveFailure = StateError('연결 실패');
    expect(await controller.finishRun(), isNull);
    expect(controller.runSession!.isFinished, isTrue);
    expect(controller.runError, isNotNull);
    final summary = historyService.attempts.single;
    await controller.startRun();
    expect(controller.runSession!.isFinished, isTrue);
    historyService.saveFailure = null;
    expect(await controller.finishRun(), same(summary));
    expect(historyService.attempts.last, same(summary));
    expect(historyService.records, hasLength(1));
    expect(controller.runSession, isNull);
  });

  test('저장 중에는 종료와 시작을 중복 실행하지 않습니다', () async {
    await controller.startRun();
    historyService.pendingSave = Completer<void>();
    final finish = controller.finishRun();
    expect(controller.savingRun, isTrue);
    expect(await controller.finishRun(), isNull);
    await controller.startRun();
    expect(historyService.attempts, hasLength(1));
    historyService.pendingSave!.complete();
    await finish;
    expect(historyService.records, hasLength(1));
    expect(controller.savingRun, isFalse);
  });

  test('백그라운드에서 러닝을 일시 정지하고 복귀 시 계속 버튼을 기다립니다', () async {
    await controller.startRun();
    final session = controller.runSession;
    await controller.setActive(false);
    expect(session!.isRunning, isFalse);
    await controller.setActive(true);
    expect(session.isRunning, isFalse);
    await controller.startRun();
    expect(controller.runSession, same(session));
    expect(session.isRunning, isTrue);
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
    await controller.start();
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
    await controller.start();
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
    await controller.start();
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
    await controller.start();
    await controller.setSharing(true);
    await controller.setActive(false);
    expect(controller.sharing, isFalse);
    expect(controller.runners, isEmpty);
    expect(service.actions.last, 'stop');
    await controller.setActive(true);
    expect(controller.position, isNotNull);
    expect(controller.sharing, isFalse);
  });

  test('미인증 또는 비공개 서버 거절을 우회하지 않습니다', () async {
    service.publishFailure = const PostgrestException(
      message: '전화번호 인증이 필요합니다.',
      code: '42501',
    );
    await controller.start();
    await controller.setSharing(true);
    expect(controller.sharing, isFalse);
    expect(controller.sharingError, '전화번호 인증이 필요합니다.');
    expect(service.onChanged, isNull);
  });

  test('공유 중 GPS 정확도가 나빠지면 마지막 위치를 삭제합니다', () async {
    await controller.start();
    await controller.setSharing(true);
    location.updates.add(testFix(accuracy: 500));
    await Future<void>.delayed(Duration.zero);
    expect(controller.sharing, isFalse);
    expect(service.actions.last, 'stop');
    expect(controller.position, isNull);
  });

  test('실시간 변경 신호로 갱신하고 연결 중단 시 이전 위치를 숨깁니다', () async {
    await controller.start();
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
