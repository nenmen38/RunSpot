import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../run_history/models/run_record.dart';

/// 기록의 시작·종료 시각 사이에 건강 앱이 집계한 분당 걸음 수입니다.
Future<int?> readShareCadence(
  RunRecord record, {
  required bool Function() canRead,
}) async {
  final elapsed = record.endedAt.difference(record.startedAt);
  if (!canRead() ||
      kIsWeb ||
      elapsed < const Duration(seconds: 1) ||
      elapsed > const Duration(days: 7) ||
      (defaultTargetPlatform != TargetPlatform.iOS &&
          defaultTargetPlatform != TargetPlatform.android)) {
    return null;
  }
  final health = Health();
  await health.configure();
  if (!canRead()) return null;
  const types = [HealthDataType.STEPS];
  final authorized = await health.requestAuthorization(
    types,
    permissions: [HealthDataAccess.READ],
  );
  if (!authorized || !canRead()) return null;
  // 두 기기의 걸음 수를 직접 합치지 않고 건강 앱의 집계를 사용합니다.
  final steps = await health.getTotalStepsInInterval(
    record.startedAt,
    record.endedAt,
    includeManualEntry: defaultTargetPlatform == TargetPlatform.android,
  );
  if (!canRead() || steps == null || steps <= 0) return null;
  final cadence =
      (steps * Duration.millisecondsPerMinute / elapsed.inMilliseconds).round();
  return cadence > 0 ? cadence : null;
}
