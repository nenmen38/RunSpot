import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/home/run_guide/run_guide.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';
import 'package:runquest/features/settings/run_voice_settings.dart';

class _Output implements RunGuideOutput {
  final progress = <String>[];
  final spoken = <String>[];
  @override
  Future<void> showProgress(String text) async => progress.add(text);
  @override
  Future<void> speak(String text) async => spoken.add(text);
}

class _Store implements AppearanceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('음성 안내는 기본으로 켜져 있고 끈 설정을 기억합니다', () async {
    final store = _Store();
    final first = RunVoiceSettings(store: store);
    await first.load();
    expect(first.enabled, isTrue);
    await first.setEnabled(false);
    final second = RunVoiceSettings(store: store);
    await second.load();
    expect(second.enabled, isFalse);
  });

  // 위치는 1분 안의 것만 쓰므로 50초 전부터 2초마다 60m씩 달린 것으로 만듭니다.
  final origin = DateTime.now().subtract(const Duration(seconds: 50));
  LocationFix fix(int step) => LocationFix(
    latitude: 37.5 + step * 60 / 111320,
    longitude: 127,
    accuracy: 5,
    recordedAt: origin.add(Duration(seconds: step * 2)),
  );

  test('1km를 지날 때 한 번만 구간 기록을 읽고 알림은 5초 간격으로 바꿉니다', () {
    final output = _Output();
    var now = origin;
    final guide = RunGuide(output, now: () => now);
    final session = RunSession(fix(0));
    guide.update(session);
    expect(output.progress, ['0.00km · 00:00']);

    for (var step = 1; step <= 18; step++) {
      session.accept(fix(step));
      now = fix(step).recordedAt;
      guide.update(session);
    }
    // 2초마다 위치가 와도 알림은 5초에 한 번만 바꿉니다.
    expect(output.progress.length, inInclusiveRange(7, 9));
    expect(output.progress.last, startsWith('1.0'));
    expect(session.completedSplits, hasLength(1));
    expect(output.spoken, hasLength(1));
    expect(output.spoken.single, startsWith('1킬로미터. 이번 구간 '));
    // 측정 시간은 실제 시계로 재므로 여기서는 문장 형식만 확인합니다.
    expect(output.spoken.single, contains('총 시간'));

    // 같은 구간은 다시 읽지 않습니다.
    session.accept(fix(19));
    guide.update(session);
    expect(output.spoken, hasLength(1));
    session.finish();
  });

  test('음성 안내를 끄면 읽지 않고, 다시 켜도 지난 구간을 몰아서 읽지 않습니다', () {
    final output = _Output();
    var voice = false;
    final guide = RunGuide(output, voiceEnabled: () => voice);
    final session = RunSession(fix(0));
    for (var step = 1; step <= 18; step++) {
      session.accept(fix(step));
      guide.update(session);
    }
    expect(session.completedSplits, hasLength(1));
    expect(output.spoken, isEmpty);
    voice = true;
    session.accept(fix(19));
    guide.update(session);
    expect(output.spoken, isEmpty);
    session.finish();
  });

  test('일시 정지 중에는 알림을 바꾸지 않습니다', () {
    final output = _Output();
    final guide = RunGuide(output);
    final session = RunSession(fix(0))..pause();
    guide.update(session);
    expect(output.progress, isEmpty);
    session.finish();
  });

  test('시간을 듣기 쉬운 말로 바꿉니다', () {
    expect(
      RunGuide.spokenDuration(const Duration(minutes: 5, seconds: 40)),
      '5분 40초',
    );
    expect(RunGuide.spokenDuration(const Duration(minutes: 6)), '6분');
    expect(RunGuide.spokenDuration(const Duration(seconds: 45)), '45초');
    expect(
      RunGuide.spokenDuration(const Duration(hours: 1, minutes: 2, seconds: 5)),
      '1시간 2분 5초',
    );
    expect(
      RunGuide.kilometerAnnouncement(
        kilometers: 3,
        splitDuration: const Duration(minutes: 5, seconds: 40),
        total: const Duration(minutes: 17, seconds: 2),
        averagePace: const Duration(minutes: 5, seconds: 41),
      ),
      '3킬로미터. 이번 구간 5분 40초. 총 시간 17분 2초. 평균 페이스 5분 41초.',
    );
  });
}
