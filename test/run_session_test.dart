import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/run_session.dart';

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
    session.accept(fix(37.568, 2));
    session.accept(fix(37.568, 1));
    expect(session.distanceMeters, distance);
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
    session.finish();
  });
}
