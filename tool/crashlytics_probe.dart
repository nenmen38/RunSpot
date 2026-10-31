import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:runquest/app/bootstrap.dart';
import 'package:runquest/app/run_quest_app.dart';
import 'package:runquest/features/diagnostics/error_reporter.dart';

/// 팀원의 출시 모드 검증 전용 진입점입니다. 일반 앱 빌드에서는 실행되지 않습니다.
/// 실제 충돌 없이 고정된 진단 이벤트와 정제된 앱 코드 위치만 기록합니다.
Future<void> main() async {
  if (!kReleaseMode) {
    throw UnsupportedError('진단 검증은 출시 빌드에서 실행해 주세요.');
  }
  await initializeApp();
  runApp(const RunQuestApp());
  await FirebaseCrashlytics.instance.recordError(
    'runspot_diagnostics_probe',
    StackTrace.fromString(ErrorReporter.sanitizedStack(StackTrace.current)),
    fatal: false,
    reason: '출시 모드의 오류 수집 연결 검증',
  );
  await FirebaseCrashlytics.instance.sendUnsentReports();
}
