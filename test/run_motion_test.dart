import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/data/run_checkpoint_store.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/run_motion_tracker.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/data/run_outbox.dart';
import 'package:runquest/features/run_history/models/run_motion_evidence.dart';
import 'package:runquest/features/run_history/models/run_split.dart';
import 'package:runquest/features/run_history/widgets/run_splits_panel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final origin = DateTime.now().subtract(const Duration(seconds: 50));
  LocationFix fix(int second, {double latitude = 37, double accuracy = 5}) =>
      LocationFix(
        latitude: latitude,
        longitude: 127,
        accuracy: accuracy,
        recordedAt: origin.add(Duration(seconds: second)),
      );

  test('표본을 5초 간격으로 보존하고 마지막 표본과 정확도를 잃지 않습니다', () {
    final tracker = RunMotionTracker();
    for (var i = 0; i <= 12; i++) {
      tracker.accept(fix(i));
    }
    final data = tracker.snapshot();
    expect(
      data.map((v) => v[0]),
      [0, 5, 10, 12].map((s) => origin.millisecondsSinceEpoch + s * 1000),
    );
    expect(data.last[3], 5);
    expect(() => data.last[1] = 0, throwsUnsupportedError);
    expect(RunMotionTracker.decode(data), data);
  });

  test('GPS 점프·낮은 정확도·단절·일시 정지 뒤에는 연속 판정하지 않습니다', () {
    final tracker = RunMotionTracker();
    tracker.accept(fix(0));
    tracker.accept(fix(5));
    tracker.accept(fix(6, latitude: 38));
    tracker.accept(fix(11, latitude: 38));
    tracker.accept(fix(12, accuracy: 50));
    tracker.accept(fix(17, latitude: 38));
    tracker.accept(fix(30, latitude: 38));
    tracker.breakSegment();
    tracker.accept(fix(35, latitude: 38));
    final segments = tracker.snapshot().map((v) => v[4]).toList();
    expect(segments, [0, 0, 1, 2, 3, 4]);
    final restored = RunMotionTracker(restored: tracker.snapshot());
    restored.accept(fix(40, latitude: 38));
    expect(restored.snapshot().last[4], greaterThan(segments.last));
  });

  test('거리 누적에서도 GPS 점프와 부정확한 위치를 연결하지 않습니다', () {
    final run = RunSession(fix(0));
    run.accept(fix(1, latitude: 38));
    expect(run.distanceMeters, 0);
    run.accept(fix(5, latitude: 38.0001));
    expect(run.distanceMeters, closeTo(11.1, 1));
    run.accept(fix(6, latitude: 38.01, accuracy: 30));
    run.accept(fix(7, latitude: 38.0002));
    expect(run.distanceMeters, closeTo(11.1, 1));
    run.finish();
  });

  test('러닝 시작 전 캐시 위치와 역전 시각은 측정 증거에 포함하지 않습니다', () {
    final tracker = RunMotionTracker(notBefore: fix(5).recordedAt);
    tracker.accept(fix(0));
    tracker.accept(fix(5));
    tracker.accept(fix(10));
    tracker.accept(fix(6));
    expect(
      tracker.snapshot().map((v) => v[0]),
      [5, 10].map((s) => origin.millisecondsSinceEpoch + s * 1000),
    );
    expect(
      () => RunMotionTracker.decode([
        [1, 37, 127, 5, 0],
        [1, 37, 127, 5, 0],
      ]),
      throwsFormatException,
    );
  });

  test('기기 저장·복구·재전송에서도 측정 원본과 구간 경계를 보존합니다', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('runspot-motion-');
    final outbox = SqliteRunOutbox(
      ownerId: 'owner',
      namespace: 'project',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/outbox.sqlite',
    );
    final checkpoint = SqliteRunCheckpointStore(
      ownerId: 'owner',
      namespace: 'project',
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/checkpoint.sqlite',
    );
    addTearDown(() async {
      await outbox.close();
      await checkpoint.close();
      await dir.delete(recursive: true);
    });
    final tracker = RunMotionTracker()
      ..accept(fix(0))
      ..accept(fix(5));
    final summary = RunSummary(
      clientRunId: 'run',
      startedAt: origin,
      endedAt: origin.add(const Duration(seconds: 10)),
      distanceMeters: 0,
      duration: const Duration(seconds: 10),
      splits: const [],
      motionSamples: tracker.snapshot(),
    );
    await outbox.put(summary);
    await checkpoint.save(RunCheckpoint(summary, finished: false));
    expect((await outbox.list()).single.motionSamples, summary.motionSamples);
    final restored = (await checkpoint.load())!.summary;
    expect(restored.motionSamples, summary.motionSamples);
    final run = RunSession.restore(restored)
      ..resume(fix(10))
      ..accept(fix(15));
    final data = run.finish().motionSamples!;
    expect(data.last[4], greaterThan(data.first[4]));
    await expectLater(
      outbox.put(
        RunSummary(
          clientRunId: summary.clientRunId,
          startedAt: summary.startedAt,
          endedAt: summary.endedAt,
          distanceMeters: 0,
          duration: summary.duration,
          splits: const [],
          motionSamples: const [],
        ),
      ),
      throwsA(isA<RunOutboxException>()),
    );
  });

  testWidgets('새 기록은 지속 속도 증거만 표시하고 1km 속도만으로 경고하지 않습니다', (tester) async {
    Future<void> show(List<RunMotionEvidence> evidence) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunSplitsPanel(
            splits: const [
              RunSplit(distanceMeters: 1000, duration: Duration(seconds: 100)),
            ],
            motionEvidence: evidence,
          ),
        ),
      ),
    );
    await show(const []);
    expect(find.text('속도 확인 필요'), findsNothing);
    await show(const [
      RunMotionEvidence(
        startSeconds: 30,
        endSeconds: 60,
        speedKmh: 30,
        accuracyMeters: 5,
      ),
    ]);
    expect(find.text('속도 확인 구간'), findsOneWidget);
    expect(find.textContaining('30.0 km/h'), findsOneWidget);
    expect(find.textContaining('정확도'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
