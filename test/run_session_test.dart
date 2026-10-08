import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/home/models/run_pace.dart';

void main() {
  final origin = DateTime.now().subtract(const Duration(seconds: 50));
  LocationFix fix(double latitude, int seconds, {double accuracy = 5}) =>
      LocationFix(
        latitude: latitude,
        longitude: 126.978,
        accuracy: accuracy,
        recordedAt: origin.add(Duration(seconds: seconds)),
      );

  test('GPS 흔들림과 중복 위치를 제외하고 이동 거리를 누적합니다', () {
    final session = RunSession(fix(37.5665, 0));
    session.accept(fix(37.566501, 1));
    expect(session.distanceMeters, 0);
    session.accept(fix(37.567, 2));
    expect(session.distanceMeters, closeTo(55.6, 1));
    final distance = session.distanceMeters;
    expect(session.routeSegments.single, hasLength(2));
    session.accept(fix(37.568, 2));
    session.accept(fix(37.568, 1));
    expect(session.distanceMeters, distance);
    expect(session.routeSegments.single, hasLength(2));
    session.finish();
  });

  test('일시 정지 중 이동과 재개 전 위치 간격은 더하지 않습니다', () {
    final session = RunSession(fix(37.5665, 0));
    session.accept(fix(37.567, 2));
    final distance = session.distanceMeters;
    session.pause();
    final duration = session.duration;
    session.accept(fix(37.57, 3));
    expect(session.distanceMeters, distance);
    expect(session.duration, duration);
    session.resume(fix(37.57, 4));
    session.accept(fix(37.5705, 6));
    final summary = session.finish();
    expect(summary.distanceMeters, closeTo(distance + 55.6, 1));
    expect(session.routeSegments, hasLength(2));
    expect(session.routeSegments.map((segment) => segment.length), [2, 2]);
    expect(session.routeSegments.first.last.latitude, 37.567);
    expect(session.routeSegments.last.first.latitude, 37.57);
    expect(session.currentPace, isNull);
    expect(session.isRunning, isFalse);
    expect(session.finish(), same(summary));
    expect(summary.clientRunId, isNotEmpty);
    expect(summary.endedAt.isAfter(summary.startedAt), isTrue);
    session.resume(fix(37.58, 8));
    expect(session.isRunning, isFalse);
  });

  test('위치 중단과 부정확한 GPS 이후 간격은 추정하지 않습니다', () {
    final session = RunSession(fix(37.5665, 0));
    session.accept(fix(37.57, 35));
    expect(session.distanceMeters, 0);
    session.accept(fix(37.571, 36, accuracy: 500));
    session.accept(fix(37.572, 37));
    expect(session.distanceMeters, 0);
    session.accept(fix(37.5725, 39));
    expect(session.distanceMeters, closeTo(55.6, 1));
    expect(session.routeSegments.map((segment) => segment.length), [1, 1, 2]);
    session.finish();
  });

  test('경로는 읽기 전용이며 새 GPS 이동이 없으면 같은 스냅샷을 유지합니다', () {
    final session = RunSession(fix(37.5665, 0));
    session.accept(fix(37.567, 5));
    final route = session.routeSegments;
    expect(session.routeSegments, same(route));
    expect(() => route.clear(), throwsUnsupportedError);
    expect(() => route.single.clear(), throwsUnsupportedError);
    session.accept(fix(37.5675, 10));
    expect(route.single, hasLength(2));
    expect(session.routeSegments.single, hasLength(3));
    session.finish();
  });

  test('현재 페이스는 정지·위치 단절·재개 시 초기화합니다', () {
    var now = fix(37.5665, 0).recordedAt;
    final session = RunSession(fix(37.5665, 0), paceNow: () => now);
    now = fix(37.567, 10).recordedAt;
    session.accept(fix(37.567, 10));
    expect(session.currentPace, const Duration(seconds: 180));
    session.pause();
    expect(session.currentPace, isNull);
    session.resume(fix(37.57, 15));
    expect(session.currentPace, isNull);
    now = fix(37.5705, 25).recordedAt;
    session.accept(fix(37.5705, 25));
    expect(session.currentPace, isNotNull);
    session.accept(fix(37.58, 26, accuracy: 500));
    expect(session.currentPace, isNull);
    session.finish();
  });

  test('잘못된 시작 좌표는 경로에 포함하지 않습니다', () {
    final session = RunSession(fix(37.5665, 0, accuracy: 500));
    expect(session.routeSegments, isEmpty);
    session.accept(fix(37.567, 5));
    expect(session.routeSegments.single, hasLength(1));
    expect(session.distanceMeters, 0);
    session.finish();
  });

  test('평균 페이스는 전체 누적 거리와 일시 정지를 뺀 측정 시간을 사용합니다', () async {
    final session = RunSession(fix(37.5665, 0));
    session.accept(fix(37.567, 10));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    session.pause();
    expect(session.averagePace, isNotNull);
    expect(
      session.averagePace,
      calculateRunPace(session.distanceMeters, session.duration),
    );
    final pace = session.averagePace;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(session.averagePace, pace);
    session.finish();
  });
}
