import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/feedback/review_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 공유 환경설정 플러그인의 메모리 저장소로 기기 저장을 검증합니다.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late DateTime now;
  late int asked;
  late ReviewPrompt prompt;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    now = DateTime(2026, 11, 1);
    asked = 0;
    prompt = ReviewPrompt(
      request: () async => asked++,
      available: () async => true,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
  });

  test('좋은 일이 없으면 묻지 않습니다', () async {
    await prompt.remember();
    now = now.add(const Duration(days: 10));
    expect(await prompt.askIfHappy(completedRuns: 10), isFalse);
    expect(asked, 0);
  });

  test('앱을 쓴 지 3일, 기록 3개가 넘어야 하고 60일에 한 번, 최대 3번만 묻습니다', () async {
    await prompt.remember();
    prompt.markHappyMoment();
    expect(await prompt.askIfHappy(completedRuns: 5), isFalse, reason: '처음 3일');
    now = now.add(const Duration(days: 4));
    prompt.markHappyMoment();
    expect(await prompt.askIfHappy(completedRuns: 2), isFalse, reason: '기록 2개');
    prompt.markHappyMoment();
    expect(await prompt.askIfHappy(completedRuns: 3), isTrue);
    expect(asked, 1);

    now = now.add(const Duration(days: 30));
    prompt.markHappyMoment();
    expect(await prompt.askIfHappy(completedRuns: 9), isFalse, reason: '60일 안');

    for (var i = 0; i < 4; i++) {
      now = now.add(const Duration(days: 61));
      prompt.markHappyMoment();
      await prompt.askIfHappy(completedRuns: 20);
    }
    expect(asked, ReviewPrompt.maxAsks);
  });

  test('평가 창을 쓸 수 없는 폰에서는 묻지 않고 횟수도 세지 않습니다', () async {
    var available = false;
    prompt = ReviewPrompt(
      request: () async => asked++,
      available: () async => available,
      preferences: SharedPreferencesAsync(),
      clock: () => now,
    );
    await prompt.remember();
    now = now.add(const Duration(days: 5));
    prompt.markHappyMoment();
    expect(await prompt.askIfHappy(completedRuns: 5), isFalse);
    available = true;
    prompt.markHappyMoment();
    expect(await prompt.askIfHappy(completedRuns: 5), isTrue);
  });
}
