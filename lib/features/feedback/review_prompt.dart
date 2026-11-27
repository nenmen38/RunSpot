import 'dart:async';

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 기분 좋은 순간(개인 최고 기록·레벨 업) 뒤에 플레이스토어 평가 창을 띄웁니다.
///
/// 구글 정책에 따라 평가 창 앞에 '마음에 드세요?' 같은 질문을 하지 않고 공식 창만 띄웁니다.
/// 너무 자주 묻지 않도록 다음을 모두 지킬 때만 띄웁니다.
/// - 러닝 기록이 [minRuns]개 이상
/// - 앱을 처음 쓴 지 [minAge] 이상 지남
/// - 마지막으로 물은 지 [interval] 이상 지남
/// - 지금까지 물은 횟수가 [maxAsks]번 미만
class ReviewPrompt {
  ReviewPrompt({
    Future<void> Function()? request,
    Future<bool> Function()? available,
    SharedPreferencesAsync? preferences,
    DateTime Function()? clock,
  }) : _request = request ?? InAppReview.instance.requestReview,
       _available = available ?? InAppReview.instance.isAvailable,
       // 저장소는 처음 쓸 때 열기 위해 따로 둡니다.
       // ignore: prefer_initializing_formals
       _preferences = preferences,
       _clock = clock ?? DateTime.now;

  static ReviewPrompt instance = ReviewPrompt();

  static const minRuns = 3;
  static const minAge = Duration(days: 3);
  static const interval = Duration(days: 60);
  static const maxAsks = 3;

  static const _firstSeenKey = 'review_prompt.first_seen';
  static const _lastAskedKey = 'review_prompt.last_asked';
  static const _countKey = 'review_prompt.count';

  final Future<void> Function() _request;
  final Future<bool> Function() _available;
  SharedPreferencesAsync? _preferences;

  /// 저장소는 처음 쓸 때 엽니다(저장소가 없는 환경에서도 앱이 멈추지 않게).
  SharedPreferencesAsync get _prefs =>
      _preferences ??= SharedPreferencesAsync();
  final DateTime Function() _clock;

  bool _happy = false;

  /// 개인 최고 기록이나 레벨 업처럼 기분 좋은 일이 있었다고 기억합니다.
  void markHappyMoment() => _happy = true;

  /// 앱을 처음 쓴 날을 기록해 둡니다(이미 있으면 그대로).
  Future<void> remember() async {
    try {
      if (await _prefs.getInt(_firstSeenKey) == null) {
        await _prefs.setInt(_firstSeenKey, _clock().millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  /// 좋은 일이 있었고 조건을 모두 지키면 평가 창을 띄웁니다. 띄웠으면 true입니다.
  Future<bool> askIfHappy({required int completedRuns}) async {
    if (!_happy) return false;
    _happy = false;
    try {
      if (completedRuns < minRuns) return false;
      final now = _clock();
      final first = await _prefs.getInt(_firstSeenKey);
      if (first == null) {
        await remember();
        return false;
      }
      if (now.difference(DateTime.fromMillisecondsSinceEpoch(first)) < minAge) {
        return false;
      }
      final count = await _prefs.getInt(_countKey) ?? 0;
      if (count >= maxAsks) return false;
      final last = await _prefs.getInt(_lastAskedKey);
      if (last != null &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(last)) <
              interval) {
        return false;
      }
      if (!await _available()) return false;
      await _prefs.setInt(_lastAskedKey, now.millisecondsSinceEpoch);
      await _prefs.setInt(_countKey, count + 1);
      await _request();
      return true;
    } catch (_) {
      // 평가 창을 못 띄워도 앱 사용에는 영향이 없습니다.
      return false;
    }
  }
}
