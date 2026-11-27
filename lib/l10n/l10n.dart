import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_ko.dart';

export 'generated/app_localizations.dart';

/// 화면에서 `context.l10n.runStart`처럼 번역 문구를 꺼내 씁니다.
/// 번역 설정이 없는 곳(테스트용 화면 등)에서는 기준 언어인 한국어를 씁니다.
extension AppL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this) ?? _korean;
}

final _korean = AppLocalizationsKo();
