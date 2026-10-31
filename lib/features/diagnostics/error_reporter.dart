import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// 원본 예외·좌표·계정·요청 본문을 보내지 않고 고정 분류와 앱 코드 위치만 보고합니다.
class ErrorReporter {
  static bool _enabled = false;
  static final Set<String> _reported = {};

  static Future<void> initialize() async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    // 자동 전송은 끄고 출시 실행에서만 전송합니다. 사용자 식별자·사용자 로그는 등록하지 않습니다.
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
    _enabled = kReleaseMode;
    if (_enabled) {
      // 이전 실행의 네이티브 충돌 보고서는 다음 시작 때 전송합니다.
      unawaited(
        FirebaseCrashlytics.instance.sendUnsentReports().catchError((_) {}),
      );
    } else {
      await FirebaseCrashlytics.instance.deleteUnsentReports();
      return;
    }
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(
        'flutter_framework',
        details.stack ?? StackTrace.empty,
        fatal: true,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report('unhandled_async', stack, fatal: true);
      return true;
    };
  }

  static String sanitizedStack(StackTrace stack) => stack
      .toString()
      .split('\n')
      .map(
        (line) =>
            RegExp(r'package:runquest/[a-zA-Z0-9_/]+\.dart:\d+:\d+')
                .firstMatch(line)
                ?.group(0),
      )
      .whereType<String>()
      .take(25)
      .join('\n');

  static void report(String category, StackTrace stack, {bool fatal = false}) {
    if (!_enabled ||
        !const {
          'flutter_framework',
          'unhandled_async',
          'run_storage',
          'run_upload',
          'run_tracking',
        }.contains(category)) {
      return;
    }
    final safe = sanitizedStack(stack);
    final key = '$category:$safe';
    if (_reported.length >= 30 || !_reported.add(key)) return;
    unawaited(_send(category, safe, fatal));
  }

  static Future<void> _send(String category, String stack, bool fatal) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        category,
        StackTrace.fromString(stack),
        fatal: fatal,
      );
      await FirebaseCrashlytics.instance.sendUnsentReports();
    } catch (_) {
      // 진단 전송 실패는 러닝과 기록 저장을 방해하지 않습니다.
    }
  }
}
