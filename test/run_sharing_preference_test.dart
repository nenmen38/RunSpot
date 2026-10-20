import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';
import 'support/run_sharing_preference_fake.dart';

void main() {
  late FakeRunSharingPreferenceService preference;
  late FakeLocationService location;
  late FakeRunnerService runners;
  late LiveMapController controller;
  late RunHistoryController history;
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    preference = FakeRunSharingPreferenceService();
    location = FakeLocationService();
    runners = FakeRunnerService();
    history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    controller = LiveMapController(
      locationService: location,
      runnerService: runners,
      runHistory: history,
      sharingPreferenceService: preference,
    );
  });
  tearDown(() async {
    controller.dispose();
    history.dispose();
    await location.updates.close();
  });

  test('기본 설정은 꺼짐이며 러닝 중 직접 공유 요청도 차단합니다', () async {
    await controller.loadSharingPreference();
    await controller.startRun();
    await controller.setSharing(true);
    expect(controller.shareWhileRunning, isFalse);
    expect(controller.sharing, isFalse);
    expect(runners.actions, isEmpty);
  });

  test('저장된 설정에 따라 시작과 재개 시 공유하고 정지와 종료 시 중단합니다', () async {
    preference.enabled = true;
    await controller.loadSharingPreference();
    expect(runners.actions, isEmpty);
    await controller.startRun();
    await flush();
    expect(controller.sharing, isTrue);
    controller.pauseRun();
    await flush();
    expect(controller.sharing, isFalse);
    expect(controller.shareWhileRunning, isTrue);
    await controller.startRun();
    await flush();
    expect(controller.sharing, isTrue);
    await controller.finishRun();
    await flush();
    expect(controller.sharing, isFalse);
    expect(controller.shareWhileRunning, isTrue);
    expect(runners.actions, ['publish', 'stop', 'publish', 'stop']);
  });

  test('러닝 중 설정을 켜면 저장 후 공유하고 끄면 저장 응답 전에 중단합니다', () async {
    await controller.loadSharingPreference();
    await controller.startRun();
    preference.pendingSave = Completer<void>();
    final enable = controller.setShareWhileRunning(true);
    await flush();
    expect(runners.actions, isEmpty);
    preference.pendingSave!.complete();
    await enable;
    await flush();
    expect(controller.sharing, isTrue);
    preference.pendingSave = Completer<void>();
    final disable = controller.setShareWhileRunning(false);
    expect(controller.shareWhileRunning, isFalse);
    expect(controller.sharing, isFalse);
    await flush();
    expect(runners.actions, ['publish', 'stop']);
    preference.pendingSave!.complete();
    await disable;
    expect(preference.enabled, isFalse);
  });

  test('끄기 저장 실패 시 공유는 꺼진 채로 저장을 재시도합니다', () async {
    preference.enabled = true;
    await controller.loadSharingPreference();
    await controller.startRun();
    await flush();
    preference.saveFailure = StateError('저장 실패');
    await controller.setShareWhileRunning(false);
    await flush();
    expect(controller.sharing, isFalse);
    expect(controller.shareWhileRunning, isFalse);
    expect(controller.sharingPreferenceError, isNotNull);
    preference.saveFailure = null;
    await controller.retrySharingPreference();
    expect(preference.enabled, isFalse);
    expect(preference.saves, [false, false]);
    expect(controller.sharingPreferenceError, isNull);
  });

  test('설정 조회 실패나 지연이 개인 러닝 시작을 막지 않습니다', () async {
    preference.pendingLoad = Completer<bool>();
    await controller.startRun();
    expect(controller.runSession!.isRunning, isTrue);
    expect(controller.sharing, isFalse);
    controller.pauseRun();
    preference.pendingLoad!.complete(true);
    await flush();
    expect(controller.shareWhileRunning, isTrue);
    expect(controller.sharing, isFalse);
    expect(runners.actions, isEmpty);
    preference.pendingLoad = null;
    preference.loadFailure = StateError('조회 실패');
    await controller.loadSharingPreference();
    expect(controller.shareWhileRunning, isFalse);
    expect(controller.sharingPreferenceLoaded, isFalse);
  });

  test('설정 저장 중 계정이 바뀌면 이전 동의로 위치를 공개하지 않습니다', () async {
    await controller.loadSharingPreference();
    await controller.startRun();
    preference.pendingSave = Completer<void>();
    final save = controller.setShareWhileRunning(true);
    preference.isCurrentOwner = false;
    preference.pendingSave!.complete();
    await save;
    await flush();
    expect(controller.sharing, isFalse);
    expect(controller.shareWhileRunning, isFalse);
    expect(runners.actions, isEmpty);
  });

  test('러닝이 끝난 뒤 도착한 설정 응답은 위치를 공개하지 않습니다', () async {
    preference.pendingLoad = Completer<bool>();
    await controller.startRun();
    await controller.finishRun();
    preference.pendingLoad!.complete(true);
    await flush();
    expect(controller.shareWhileRunning, isTrue);
    expect(controller.sharing, isFalse);
    expect(runners.actions, isEmpty);
  });
}
