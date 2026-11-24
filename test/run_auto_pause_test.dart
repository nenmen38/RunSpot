import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/run_session.dart';

/// 북쪽으로 [meters]만큼 떨어진 위치입니다(위도 1도 ≈ 111,320m).
LocationFix at(double meters, DateTime time, {double accuracy = 5}) =>
    LocationFix(
      latitude: 37.5 + meters / 111320,
      longitude: 127,
      accuracy: accuracy,
      recordedAt: time,
    );

void main() {
  // 앱은 1분보다 오래되었거나 미래인 위치를 버리므로, 각 시험은 59초 전부터 지금까지 안에서 진행합니다.
  late DateTime now;

  RunSession start({bool enabled = true}) {
    final base = DateTime.now().toUtc().subtract(const Duration(seconds: 59));
    now = base;
    return RunSession(
      at(0, base),
      now: () => now,
      autoPauseEnabled: () => enabled,
    );
  }

  /// 2초마다 [speed]m/s로 [seconds]초 달립니다. 돌려주는 값은 마지막 위치(m)입니다.
  double run(RunSession session, double from, int seconds, {double speed = 3}) {
    var position = from;
    for (var t = 2; t <= seconds; t += 2) {
      position += speed * 2;
      now = now.add(const Duration(seconds: 2));
      session.accept(at(position, now));
    }
    return position;
  }

  /// [seconds]초 동안 제자리에 서 있습니다(GPS가 2m 안에서 흔들림).
  void stand(RunSession session, double position, int seconds) {
    for (var t = 2; t <= seconds; t += 2) {
      now = now.add(const Duration(seconds: 2));
      session.accept(at(position + (t % 4 == 0 ? 2 : -2), now));
      session.tick();
    }
  }

  test('10초 넘게 멈추면 자동 일시정지하고 다시 달리면 같은 선으로 이어집니다', () {
    final session = start();
    var position = run(session, 0, 16);
    stand(session, position, 8);
    expect(session.isAutoPaused, isFalse, reason: '10초가 안 되면 멈추지 않습니다');
    stand(session, position, 6);
    expect(session.isAutoPaused, isTrue);
    // 자동 일시정지 중에도 측정(위치 기록)은 계속하므로 러닝 중으로 봅니다.
    expect(session.isRunning, isTrue);
    expect(session.currentPace, isNull);
    final paused = session.distanceMeters;
    stand(session, position, 10);
    expect(session.distanceMeters, paused, reason: '서 있는 동안 흔들림은 거리에 넣지 않습니다');

    position = run(session, position, 16);
    expect(session.isAutoPaused, isFalse);
    expect(session.routeSegments, hasLength(1), reason: '선이 끊기면 안 됩니다');
    expect(session.distanceMeters, closeTo(96, 12));
  });

  test('오래 멈춰 있다가 다시 달려도 선이 끊기지 않습니다', () {
    final session = start();
    final position = run(session, 0, 6);
    stand(session, position, 44);
    expect(session.isAutoPaused, isTrue);
    run(session, position, 8);
    expect(session.routeSegments, hasLength(1));
    expect(session.distanceMeters, closeTo(42, 12));
  });

  test('위치가 오지 않아도 1초 확인으로 10초 뒤 자동 일시정지합니다', () {
    final session = start();
    run(session, 0, 6);
    // 마지막으로 10m 넘게 움직인 때부터 셉니다(달리는 중엔 2~4초 전).
    now = now.add(const Duration(seconds: 5));
    session.tick();
    expect(session.isAutoPaused, isFalse);
    now = now.add(const Duration(seconds: 6));
    session.tick();
    expect(session.isAutoPaused, isTrue);
  });

  test('자동 일시정지 중 다시 시작을 눌러도 같은 선으로 이어지고, 직접 일시정지는 그대로 동작합니다', () {
    final session = start();
    final position = run(session, 0, 10);
    stand(session, position, 14);
    expect(session.isAutoPaused, isTrue);
    now = now.add(const Duration(seconds: 2));
    session.resume(at(position + 3, now));
    expect(session.isAutoPaused, isFalse);
    expect(session.routeSegments, hasLength(1));

    session.pause();
    expect(session.isRunning, isFalse);
    expect(session.isAutoPaused, isFalse);
  });

  test('자동 일시정지를 끄면 멈춰 있어도 일시정지하지 않습니다', () {
    final session = start(enabled: false);
    final position = run(session, 0, 10);
    stand(session, position, 30);
    expect(session.isAutoPaused, isFalse);
    expect(session.isRunning, isTrue);
  });

  test('멈춘 사이 차량 등으로 멀리 옮겨지면 그 거리는 넣지 않습니다', () {
    final session = start();
    final position = run(session, 0, 10);
    stand(session, position, 14);
    now = now.add(const Duration(seconds: 20));
    session.accept(at(position + 2000, now));
    expect(session.isAutoPaused, isFalse);
    expect(session.distanceMeters, closeTo(30, 8));
    expect(session.routeSegments, hasLength(2));
  });

  test('자동 일시정지 중 종료해도 기록을 그대로 저장합니다', () {
    final session = start();
    final position = run(session, 0, 40);
    stand(session, position, 14);
    final summary = session.finish();
    expect(summary.distanceMeters, closeTo(120, 12));
    expect(summary.route.segments, hasLength(1));
  });
}
