import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/run_pace.dart';
import 'package:runquest/shared/formatters/run_format.dart';

void main() {
  test('평균 페이스를 초 단위로 반올림하고 잘못된 값은 표시하지 않습니다', () {
    expect(
      calculateRunPace(3000, const Duration(minutes: 18)),
      const Duration(minutes: 6),
    );
    expect(
      calculateRunPace(1500, const Duration(seconds: 601)),
      const Duration(minutes: 6, seconds: 41),
    );
    for (final distance in [0.0, -10.0, double.nan, double.infinity]) {
      expect(calculateRunPace(distance, const Duration(minutes: 1)), isNull);
    }
    expect(calculateRunPace(100, Duration.zero), isNull);
    expect(calculateRunPace(100, const Duration(seconds: -1)), isNull);
    expect(calculateRunPace(100, const Duration(microseconds: 1)), isNull);
  });

  test('페이스를 분과 초로 표시하고 측정 전에는 대시를 표시합니다', () {
    expect(formatPaceDuration(const Duration(minutes: 6, seconds: 5)), '6:05');
    expect(
      formatPaceDuration(const Duration(minutes: 65, seconds: 1)),
      '65:01',
    );
    expect(formatPaceDuration(null), '--:--');
    expect(formatPaceDuration(Duration.zero), '--:--');
    expect(formatPaceDuration(const Duration(milliseconds: 100)), '--:--');
  });

  final origin = DateTime(2026, 10, 9, 12);
  DateTime at(int seconds) => origin.add(Duration(seconds: seconds));

  test('짧은 표본과 GPS 오차 수준의 거리는 현재 페이스로 표시하지 않습니다', () {
    var now = at(0);
    final pace = RunPace(now: () => now)..reset(0, at(0));
    expect(pace.current, isNull);
    now = at(4);
    pace.accept(20, now);
    expect(pace.current, isNull);
    pace.reset(0, at(0));
    now = at(5);
    pace.accept(5, now);
    expect(pace.current, isNull);
    now = at(10);
    pace.accept(25, now);
    expect(pace.current, const Duration(minutes: 6, seconds: 40));
  });

  test('최근 이동 구간을 묶고 오래된 표본은 계산에서 제외합니다', () {
    var now = at(0);
    final pace = RunPace(now: () => now)..reset(0, now);
    for (var seconds = 5; seconds <= 20; seconds += 5) {
      now = at(seconds);
      pace.accept(seconds * 2.5, now);
    }
    expect(pace.current, const Duration(minutes: 6, seconds: 40));
    for (var seconds = 25; seconds <= 40; seconds += 5) {
      now = at(seconds);
      pace.accept(50 + (seconds - 20) * 5, now);
    }
    expect(pace.current, const Duration(minutes: 3, seconds: 20));
  });

  test('이동하지 않거나 GPS 갱신이 끊기면 이전 페이스를 계속 표시하지 않습니다', () {
    var now = at(10);
    final pace = RunPace(now: () => now)..reset(0, at(0));
    pace.accept(25, now);
    expect(pace.current, isNotNull);
    now = at(20);
    pace.accept(25, now);
    expect(pace.current, const Duration(minutes: 13, seconds: 20));
    now = at(26);
    pace.accept(25, now);
    expect(pace.current, isNull);
    pace.reset(25, at(30));
    now = at(40);
    pace.accept(50, now);
    expect(pace.current, isNotNull);
    now = at(56);
    expect(pace.current, isNull);
  });

  test('중복 시각과 역순 표본은 현재 페이스에 반영하지 않습니다', () {
    final pace = RunPace(now: () => at(10))..reset(0, at(0));
    pace.accept(25, at(10));
    final current = pace.current;
    pace.accept(200, at(10));
    pace.accept(300, at(5));
    pace.accept(10, at(11));
    expect(pace.current, current);
    pace.clear();
    expect(pace.current, isNull);
  });
}
