import 'dart:async';

import 'package:flutter/services.dart';

import '../home/live_map_controller.dart';

/// 연결된 워치에는 현재 측정값만 전송하며 계정·경로·인증 정보는 보내지 않습니다.
class WatchBridge {
  WatchBridge(this.controller);
  final LiveMapController controller;
  static const channel = MethodChannel('runspot/watch');
  Timer? _timer;
  bool _closed = false;
  bool _busy = false;
  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (_closed || !controller.runHistory.service.isCurrentOwner) {
        return false;
      }
      if (call.method != 'command') throw MissingPluginException();
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final session = controller.runSession;
      // 지연 도착한 명령이 다른 러닝을 중단하지 않도록 세션을 확인합니다.
      if (controller.savingRun ||
          session == null ||
          args['session'] != session.clientRunId) {
        return false;
      }
      if (args['action'] == 'pause' && session.isRunning) {
        controller.pauseRun();
      } else if (args['action'] == 'resume' &&
          !session.isRunning &&
          !session.isFinished) {
        await controller.startRun();
      } else {
        return false;
      }
      await _publish();
      return identical(controller.runSession, session) &&
          (args['action'] == 'pause' ? !session.isRunning : session.isRunning);
    });
    controller.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _publish());
    await _publish();
  }

  void _changed() => unawaited(_publish());
  Future<void> _publish() async {
    if (_closed || _busy) return;
    _busy = true;
    final session = controller.runSession;
    try {
      await channel.invokeMethod<void>('state', {
        'session': session?.clientRunId ?? '',
        'state': session == null
            ? 'idle'
            : session.isFinished
            ? 'finished'
            : session.isRunning
            ? 'running'
            : 'paused',
        'distance': session?.distanceMeters ?? 0,
        'seconds': session?.duration.inSeconds ?? 0,
        'pace': session?.currentPace?.inSeconds ?? 0,
        'updated': DateTime.now().millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      // 워치 연결을 지원하지 않는 데스크톱에서는 전송하지 않습니다.
    } on PlatformException {
      // 연결이 복구되면 다음 주기에 최신 상태를 다시 전송합니다.
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
    controller.removeListener(_changed);
    channel.setMethodCallHandler(null);
    unawaited(
      channel
          .invokeMethod<void>('state', {
            'session': '',
            'state': 'idle',
            'distance': 0,
            'seconds': 0,
            'pace': 0,
            'updated': DateTime.now().millisecondsSinceEpoch,
          })
          .catchError((Object _) {}),
    );
  }
}
