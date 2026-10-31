import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/run_analysis_tracker.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/home/data/run_checkpoint_store.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/models/run_analysis_data.dart';
import 'package:runquest/features/run_history/models/run_split.dart';
import 'package:runquest/features/health/models/run_health_data.dart';
import 'package:runquest/features/run_feedback/models/run_feedback_context.dart';
import 'package:runquest/features/run_feedback/models/run_feedback_heart_summary.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final start = DateTime.now().toUtc().subtract(const Duration(hours: 1));
  LocationFix fix(
    int seconds,
    double height, {
    double error = 2,
    double accuracy = 5,
  }) => LocationFix(
    latitude: 37,
    longitude: 127,
    accuracy: accuracy,
    recordedAt: start.add(Duration(seconds: seconds)),
    altitude: height,
    altitudeAccuracy: error,
  );
  RunAnalysisData data() => RunAnalysisData.decode({
    'version': 1,
    'windows': [
      [0, 300000, 0, 300000],
      [360000, 660000, 300000, 600000],
    ],
    'pauses': [
      [300000, 360000, 0],
    ],
    'elevation': [
      [0, 1000, 30, 4],
    ],
    'gps': [
      [1, 50, 2, 1, 12000, 250, 10, 50],
    ],
  })!;
  test('일시 정지·복구 시간과 실제 활동 시각을 구분하고 고도 오차를 보존합니다', () {
    final tracker = RunAnalysisTracker(start)..resume(start, Duration.zero);
    tracker.altitude(fix(0, 100), 0);
    tracker.altitude(fix(10, 102), 50);
    tracker.altitude(fix(20, 120), 100);
    tracker.observe(fix(1, 100), 0, accepted: true);
    tracker.observe(fix(20, 100, accuracy: 50), 100, accepted: false);
    tracker.pause(
      start.add(const Duration(seconds: 30)),
      const Duration(seconds: 30),
      0,
    );
    tracker.resume(
      start.add(const Duration(seconds: 40)),
      const Duration(seconds: 30),
    );
    final snapshot = tracker.snapshot(
      start.add(const Duration(seconds: 60)),
      const Duration(seconds: 50),
    );
    expect(snapshot.windows, [
      [0, 30000, 0, 30000],
      [40000, 60000, 30000, 50000],
    ]);
    expect(snapshot.pauses, [
      [30000, 40000, 0],
    ]);
    expect(snapshot.elevation, [
      [0, 100, 20, 4],
    ]);
    expect(snapshot.gps.single, [1, 2, 1, 1, 19000, 55, 50, 2]);
    final restored = RunAnalysisTracker(start, restored: snapshot)
      ..restorePause(start.add(const Duration(seconds: 60)));
    restored.resume(
      start.add(const Duration(seconds: 90)),
      const Duration(seconds: 50),
    );
    expect(
      restored
          .snapshot(
            start.add(const Duration(seconds: 100)),
            const Duration(seconds: 60),
          )
          .pauses
          .last,
      [60000, 90000, 2],
    );
  });
  test('수직 정확도가 없거나 나쁜 고도와 GPS 단절 사이를 연결하지 않습니다', () {
    final tracker = RunAnalysisTracker(start);
    tracker.altitude(fix(0, 100), 0);
    tracker.altitude(fix(5, 200, error: 0), 50);
    tracker.altitude(fix(10, 100, error: 30), 100);
    tracker.altitude(fix(15, 100), 150);
    tracker.breakElevation();
    tracker.altitude(fix(30, 200), 200);
    expect(tracker.snapshot(start, Duration.zero).elevation, isEmpty);
  });
  test('구간 심박은 정지·미측정·구간 경계 표본을 제외하고 같은 구간에만 배정합니다', () {
    final context = RunFeedbackContext(
      startedAt: start,
      analysis: data(),
      splits: const [
        RunSplit(distanceMeters: 1000, duration: Duration(minutes: 5)),
        RunSplit(distanceMeters: 1000, duration: Duration(minutes: 5)),
      ],
    );
    final source = RunHealthSource(
      id: 'private',
      label: '워치',
      heartSamples: 4,
      averageHeartRate: 150,
      maxHeartRate: 180,
      heartObservations: [
        RunHeartObservation(
          start.add(const Duration(seconds: 100)),
          start.add(const Duration(seconds: 100)),
          140,
        ),
        RunHeartObservation(
          start.add(const Duration(seconds: 330)),
          start.add(const Duration(seconds: 330)),
          180,
        ),
        RunHeartObservation(
          start.add(const Duration(seconds: 400)),
          start.add(const Duration(seconds: 400)),
          150,
        ),
        RunHeartObservation(
          start.add(const Duration(seconds: 295)),
          start.add(const Duration(seconds: 365)),
          130,
        ),
      ],
    );
    final summary = RunFeedbackHeartSummary.fromSource(
      source,
      context: context,
    )!;
    expect(summary.segments, [
      {'index': 1, 'average_bpm': 140, 'max_bpm': 140, 'sample_count': 1},
      {'index': 2, 'average_bpm': 150, 'max_bpm': 150, 'sample_count': 1},
    ]);
    expect(RunFeedbackHeartSummary.fromSource(source)!.segments, isEmpty);
  });
  test('분석 자료는 기기 재개·전송 대기 저장소를 다시 열어도 보존합니다', () async {
    final dir = await Directory.systemTemp.createTemp('runspot-analysis-');
    addTearDown(() => dir.delete(recursive: true));
    final summary = RunSummary(
      clientRunId: 'run',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 11)),
      distanceMeters: 2000,
      duration: const Duration(minutes: 10),
      analysisData: data(),
    );
    final checkpoint = SqliteRunCheckpointStore(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/active.sqlite',
    );
    await checkpoint.save(RunCheckpoint(summary, finished: false));
    final restored = (await checkpoint.load())!.summary;
    expect(restored.analysisData!.toJson(), data().toJson());
    await checkpoint.close();
    final outbox = SqliteRunOutbox(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/outbox.sqlite',
    );
    await outbox.put(summary);
    await outbox.close();
    final reopened = SqliteRunOutbox(
      ownerId: 'owner',
      namespace: 'server',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/outbox.sqlite',
    );
    expect(
      (await reopened.list()).single.analysisData!.toJson(),
      data().toJson(),
    );
    await reopened.close();
  });
  test('기존 기록의 분석 자료를 만들지 않고 잘못된 구간은 거부합니다', () {
    expect(RunAnalysisData.decode(null), isNull);
    expect(
      () => RunAnalysisData.decode({
        ...data().toJson(),
        'windows': [
          [100, 0, 0, 100],
        ],
      }),
      throwsFormatException,
    );
  });
}
