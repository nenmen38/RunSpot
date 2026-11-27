// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navSocial => 'Social';

  @override
  String get navProfile => 'Profile';

  @override
  String get navBoard => 'Board';

  @override
  String get navItems => 'Items';

  @override
  String get runStart => 'Start run';

  @override
  String get runResume => 'Resume';

  @override
  String get runPause => 'Pause';

  @override
  String get runFinish => 'Finish run';

  @override
  String get runRetrySave => 'Retry saving';

  @override
  String get runRunning => 'Running';

  @override
  String get runRunningLocked => 'Running · controls locked';

  @override
  String get runAutoPaused => 'Auto-paused · resumes when you run';

  @override
  String get runWaitingSave => 'Waiting to save';

  @override
  String get runDistance => 'Distance';

  @override
  String get runTime => 'Time';

  @override
  String get runCurrentPace => 'Current pace';

  @override
  String get runAveragePace => 'Average pace';

  @override
  String get runHoldToUnlock => 'Hold to unlock';

  @override
  String get runLock => 'Lock';

  @override
  String get runLockTooltip => 'Lock controls';

  @override
  String get runGroupPreparing =>
      'Getting ready for the group start. Keep the app open.';

  @override
  String get runCancelPreparation => 'Cancel';

  @override
  String get countdownTitle => 'Get ready';

  @override
  String countdownLabel(int seconds) {
    return 'Run starts in $seconds s';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Done';

  @override
  String get completionTitle => 'Run complete';

  @override
  String get completionSavedOnDevice => 'Saved on device';

  @override
  String get completionResult => 'Run result';

  @override
  String get completionShareCard => 'Create share card';

  @override
  String get completionMyRecords => 'My runs';

  @override
  String get completionHide => 'Hide this run';

  @override
  String get checkSignIn => 'Please check that you are signed in.';

  @override
  String get offlineBanner =>
      'You\'re offline · runs are saved on this phone and upload when you reconnect';

  @override
  String get onlineAgain => 'Back online';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageHint => 'English covers only some screens for now.';

  @override
  String get languageSystem => 'Phone';

  @override
  String get languageKorean => '한국어';

  @override
  String get languageEnglish => 'English';
}
