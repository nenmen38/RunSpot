// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get navHome => '홈';

  @override
  String get navSocial => '소셜';

  @override
  String get navProfile => '프로필';

  @override
  String get navBoard => '게시판';

  @override
  String get navItems => '아이템';

  @override
  String get runStart => '러닝 시작';

  @override
  String get runResume => '러닝 계속';

  @override
  String get runPause => '일시 정지';

  @override
  String get runFinish => '러닝 종료';

  @override
  String get runRetrySave => '저장 재시도';

  @override
  String get runRunning => '러닝 중';

  @override
  String get runRunningLocked => '러닝 중 · 조작 잠김';

  @override
  String get runAutoPaused => '자동 일시정지 · 달리면 이어서 측정';

  @override
  String get runWaitingSave => '저장 대기';

  @override
  String get runDistance => '거리';

  @override
  String get runTime => '시간';

  @override
  String get runCurrentPace => '현재 페이스';

  @override
  String get runAveragePace => '평균 페이스';

  @override
  String get runHoldToUnlock => '길게 눌러 해제';

  @override
  String get runLock => '잠금';

  @override
  String get runLockTooltip => '조작 잠금';

  @override
  String get runGroupPreparing => '그룹 출발 준비 중입니다. 앱을 열어 두세요.';

  @override
  String get runCancelPreparation => '준비 취소';

  @override
  String get countdownTitle => '곧 출발해요';

  @override
  String countdownLabel(int seconds) {
    return '$seconds초 뒤 러닝 시작';
  }

  @override
  String get cancel => '취소';

  @override
  String get confirm => '확인';

  @override
  String get completionTitle => '러닝 완료';

  @override
  String get completionSavedOnDevice => '기기에 저장됨';

  @override
  String get completionResult => '러닝 결과';

  @override
  String get completionShareCard => '공유 카드 만들기';

  @override
  String get completionMyRecords => '내 기록';

  @override
  String get completionHide => '기록 숨기기';

  @override
  String get checkSignIn => '로그인 상태를 확인해 주세요.';

  @override
  String get offlineBanner => '오프라인이에요 · 러닝 기록은 기기에 저장되고 연결되면 올라가요';

  @override
  String get onlineAgain => '다시 연결됐어요';

  @override
  String get languageTitle => '언어';

  @override
  String get languageHint => '영어는 아직 일부 화면만 번역되어 있어요.';

  @override
  String get languageSystem => '휴대폰 언어';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageEnglish => 'English';
}
