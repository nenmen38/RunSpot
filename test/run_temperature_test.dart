import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_conditions/conditions_controller.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_temperature.dart';

import 'support/conditions_fakes.dart';
import 'support/live_map_fakes.dart';

void main() {
  test('종료 위치의 최신 기온을 추가 API 호출 없이 고정합니다', () {
    final now = DateTime.now().toUtc();
    final service = FakeConditionsService();
    final controller = ConditionsController(service);
    addTearDown(controller.dispose);
    final fix = testFix();
    controller.setLocation(fix);
    controller.data = fixture(
      now,
      temp: 23.5,
      age: const Duration(minutes: 30),
    );
    final temperature = controller.temperatureAt(fix, now)!;
    expect(temperature.celsius, 23.5);
    expect(temperature.observedAt, now.subtract(const Duration(minutes: 30)));
    expect(service.calls, 0);
    expect(controller.temperatureAt(testFix(latitude: 35), now), isNull);
    expect(controller.temperatureAt(testFix(accuracy: 101), now), isNull);
    controller.setLocation(testFix(latitude: 35));
    expect(controller.temperatureAt(fix, now), isNull);
  });
  test('오래된 관측·미래 시각·잘못된 기온은 기록하지 않습니다', () {
    final now = DateTime.now().toUtc();
    final controller = ConditionsController(FakeConditionsService());
    addTearDown(controller.dispose);
    final fix = testFix();
    controller.setLocation(fix);
    for (final age in [
      const Duration(minutes: 121),
      const Duration(minutes: -16),
    ]) {
      controller.data = fixture(now, age: age);
      expect(controller.temperatureAt(fix, now), isNull);
    }
    for (final temp in [double.nan, double.infinity, -81.0, 61.0]) {
      controller.data = fixture(now, temp: temp);
      expect(controller.temperatureAt(fix, now), isNull);
    }
    controller.data = null;
    expect(controller.temperatureAt(fix, now), isNull);
  });
  test('종료 재시도는 같은 기온과 종료 시각을 사용합니다', () {
    final session = RunSession(testFix());
    var calls = 0;
    final summary = session.finish(
      temperatureAtEnd: (endedAt) {
        calls++;
        return RunTemperature(celsius: -3.2, observedAt: endedAt);
      },
    );
    expect(
      session.finish(
        temperatureAtEnd: (_) {
          throw StateError('재조회 금지');
        },
      ),
      same(summary),
    );
    expect(calls, 1);
    expect(RunRecord.pending(summary).temperature, same(summary.temperature));
    expect(summary.temperature!.isFreshAt(summary.endedAt), isTrue);
    expect(summary.temperature!.label, '-3.2 °C');
  });
  test('서버 기온을 읽고 이전 기록의 빈 기온을 보존합니다', () {
    final row = <String, dynamic>{
      'id': 'record',
      'client_run_id': 'client',
      'started_at': '2026-10-13T00:00:00Z',
      'ended_at': '2026-10-13T01:00:00Z',
      'distance_m': 100,
      'duration_sec': 60,
    };
    expect(RunRecord.fromJson(row).temperature, isNull);
    row.addAll(
      RunTemperature(
        celsius: 0,
        observedAt: DateTime.utc(2026, 10, 13),
      ).toJson(),
    );
    final temperature = RunRecord.fromJson(row).temperature!;
    expect(temperature.celsius, 0);
    expect(temperature.label, '0.0 °C');
    expect(temperature.observedAt.isUtc, isTrue);
  });
}
