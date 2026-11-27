import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ko.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ko'),
  ];

  /// 하단 메뉴
  ///
  /// In ko, this message translates to:
  /// **'홈'**
  String get navHome;

  /// 하단 메뉴
  ///
  /// In ko, this message translates to:
  /// **'소셜'**
  String get navSocial;

  /// 하단 메뉴
  ///
  /// In ko, this message translates to:
  /// **'프로필'**
  String get navProfile;

  /// 하단 메뉴
  ///
  /// In ko, this message translates to:
  /// **'게시판'**
  String get navBoard;

  /// 하단 메뉴
  ///
  /// In ko, this message translates to:
  /// **'아이템'**
  String get navItems;

  /// 러닝 버튼
  ///
  /// In ko, this message translates to:
  /// **'러닝 시작'**
  String get runStart;

  /// 러닝 버튼
  ///
  /// In ko, this message translates to:
  /// **'러닝 계속'**
  String get runResume;

  /// 러닝 버튼·상태
  ///
  /// In ko, this message translates to:
  /// **'일시 정지'**
  String get runPause;

  /// 러닝 버튼
  ///
  /// In ko, this message translates to:
  /// **'러닝 종료'**
  String get runFinish;

  /// 러닝 버튼
  ///
  /// In ko, this message translates to:
  /// **'저장 재시도'**
  String get runRetrySave;

  /// 러닝 상태
  ///
  /// In ko, this message translates to:
  /// **'러닝 중'**
  String get runRunning;

  /// 러닝 상태
  ///
  /// In ko, this message translates to:
  /// **'러닝 중 · 조작 잠김'**
  String get runRunningLocked;

  /// 러닝 상태
  ///
  /// In ko, this message translates to:
  /// **'자동 일시정지 · 달리면 이어서 측정'**
  String get runAutoPaused;

  /// 러닝 상태
  ///
  /// In ko, this message translates to:
  /// **'저장 대기'**
  String get runWaitingSave;

  /// 러닝 지표
  ///
  /// In ko, this message translates to:
  /// **'거리'**
  String get runDistance;

  /// 러닝 지표
  ///
  /// In ko, this message translates to:
  /// **'시간'**
  String get runTime;

  /// 러닝 지표
  ///
  /// In ko, this message translates to:
  /// **'현재 페이스'**
  String get runCurrentPace;

  /// 러닝 지표
  ///
  /// In ko, this message translates to:
  /// **'평균 페이스'**
  String get runAveragePace;

  /// 잠금 해제 안내
  ///
  /// In ko, this message translates to:
  /// **'길게 눌러 해제'**
  String get runHoldToUnlock;

  /// 잠금 버튼
  ///
  /// In ko, this message translates to:
  /// **'잠금'**
  String get runLock;

  /// 잠금 버튼 설명
  ///
  /// In ko, this message translates to:
  /// **'조작 잠금'**
  String get runLockTooltip;

  /// 함께 달리기 준비
  ///
  /// In ko, this message translates to:
  /// **'그룹 출발 준비 중입니다. 앱을 열어 두세요.'**
  String get runGroupPreparing;

  /// 함께 달리기 준비 취소
  ///
  /// In ko, this message translates to:
  /// **'준비 취소'**
  String get runCancelPreparation;

  /// 출발 카운트다운
  ///
  /// In ko, this message translates to:
  /// **'곧 출발해요'**
  String get countdownTitle;

  /// 출발 카운트다운 낭독
  ///
  /// In ko, this message translates to:
  /// **'{seconds}초 뒤 러닝 시작'**
  String countdownLabel(int seconds);

  /// 공통
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get cancel;

  /// 공통
  ///
  /// In ko, this message translates to:
  /// **'확인'**
  String get confirm;

  /// 완료 화면 제목
  ///
  /// In ko, this message translates to:
  /// **'러닝 완료'**
  String get completionTitle;

  /// 완료 화면 제목(오프라인)
  ///
  /// In ko, this message translates to:
  /// **'기기에 저장됨'**
  String get completionSavedOnDevice;

  /// 완료 화면 제목(다른 계정)
  ///
  /// In ko, this message translates to:
  /// **'러닝 결과'**
  String get completionResult;

  /// 완료 화면 버튼
  ///
  /// In ko, this message translates to:
  /// **'공유 카드 만들기'**
  String get completionShareCard;

  /// 완료 화면 버튼
  ///
  /// In ko, this message translates to:
  /// **'내 기록'**
  String get completionMyRecords;

  /// 완료 화면 버튼
  ///
  /// In ko, this message translates to:
  /// **'기록 숨기기'**
  String get completionHide;

  /// 공통 안내
  ///
  /// In ko, this message translates to:
  /// **'로그인 상태를 확인해 주세요.'**
  String get checkSignIn;

  /// 오프라인 띠
  ///
  /// In ko, this message translates to:
  /// **'오프라인이에요 · 러닝 기록은 기기에 저장되고 연결되면 올라가요'**
  String get offlineBanner;

  /// 다시 연결 띠
  ///
  /// In ko, this message translates to:
  /// **'다시 연결됐어요'**
  String get onlineAgain;

  /// 설정 > 화면
  ///
  /// In ko, this message translates to:
  /// **'언어'**
  String get languageTitle;

  /// 설정 > 화면
  ///
  /// In ko, this message translates to:
  /// **'영어는 아직 일부 화면만 번역되어 있어요.'**
  String get languageHint;

  /// 언어 선택
  ///
  /// In ko, this message translates to:
  /// **'휴대폰 언어'**
  String get languageSystem;

  /// 언어 선택
  ///
  /// In ko, this message translates to:
  /// **'한국어'**
  String get languageKorean;

  /// 언어 선택
  ///
  /// In ko, this message translates to:
  /// **'English'**
  String get languageEnglish;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ko'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ko':
      return AppLocalizationsKo();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
