import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/watch/watch_bridge.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('워치 명령은 현재 러닝만 일시정지하며 다른 기록이나 종료 명령은 거부합니다', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final published = <Map>[];
    messenger.setMockMethodCallHandler(WatchBridge.channel, (call) async {
      published.add(call.arguments as Map);
      return null;
    });
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    controller.runSession = RunSession(testFix());
    final bridge = WatchBridge(controller);
    await bridge.start();
    Future<Object?> command(String action, String session) async {
      final answer = Completer<Object?>();
      messenger.handlePlatformMessage(
        'runspot/watch',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('command', {'action': action, 'session': session}),
        ),
        (bytes) {
          answer.complete(const StandardMethodCodec().decodeEnvelope(bytes!));
        },
      );
      return answer.future;
    }

    expect(await command('pause', 'old-session'), false);
    expect(controller.runSession!.isRunning, true);
    expect(await command('finish', controller.runSession!.clientRunId), false);
    expect(await command('pause', controller.runSession!.clientRunId), true);
    expect(controller.runSession!.isRunning, false);
    expect(
      published.first.keys,
      containsAll(['session', 'distance', 'seconds', 'pace', 'updated']),
    );
    expect(published.first.containsKey('route'), false);
    bridge.dispose();
    controller.dispose();
    history.dispose();
    await location.updates.close();
    messenger.setMockMethodCallHandler(WatchBridge.channel, null);
  });
}
