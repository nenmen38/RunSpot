import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 화면 테마 선택입니다. 기기 설정을 따르거나 라이트·다크로 고정합니다.
enum AppThemeChoice {
  system('system', '기기 설정', ThemeMode.system),
  light('light', '라이트', ThemeMode.light),
  dark('dark', '다크', ThemeMode.dark);

  const AppThemeChoice(this.code, this.label, this.mode);
  final String code;
  final String label;
  final ThemeMode mode;
}

/// 앱 글자 크기입니다. 기기의 글자 크기 설정에 곱해서 적용합니다.
enum AppTextSize {
  small('small', '작게', .9),
  normal('normal', '기본', 1),
  large('large', '크게', 1.15),
  extraLarge('extra_large', '아주 크게', 1.3);

  const AppTextSize(this.code, this.label, this.scale);
  final String code;
  final String label;
  final double scale;
}

/// 화면 설정을 저장하는 곳입니다. 앱에서는 기기 저장소를, 테스트에서는 메모리를 씁니다.
abstract interface class AppearanceStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class DeviceAppearanceStore implements AppearanceStore {
  final _prefs = SharedPreferencesAsync();
  @override
  Future<String?> read(String key) => _prefs.getString(key);
  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

/// 다크 모드와 글자 크기 설정을 기기에 저장하고 앱 전체에 알립니다.
class AppAppearance extends ChangeNotifier {
  AppAppearance({AppearanceStore? store}) : _given = store;

  static final instance = AppAppearance();
  static const _themeKey = 'appearance.theme';
  static const _textKey = 'appearance.text_size';

  final AppearanceStore? _given;
  late final AppearanceStore _prefs = _given ?? DeviceAppearanceStore();

  AppThemeChoice theme = AppThemeChoice.system;
  AppTextSize textSize = AppTextSize.normal;

  /// 저장한 설정을 불러옵니다. 실패하면 기본값(기기 설정·기본 크기)을 씁니다.
  Future<void> load() async {
    try {
      final themeCode = await _prefs.read(_themeKey);
      final textCode = await _prefs.read(_textKey);
      theme =
          AppThemeChoice.values
              .where((choice) => choice.code == themeCode)
              .firstOrNull ??
          AppThemeChoice.system;
      textSize =
          AppTextSize.values
              .where((size) => size.code == textCode)
              .firstOrNull ??
          AppTextSize.normal;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setTheme(AppThemeChoice value) async {
    if (theme == value) return;
    theme = value;
    notifyListeners();
    try {
      await _prefs.write(_themeKey, value.code);
    } catch (_) {}
  }

  Future<void> setTextSize(AppTextSize value) async {
    if (textSize == value) return;
    textSize = value;
    notifyListeners();
    try {
      await _prefs.write(_textKey, value.code);
    } catch (_) {}
  }
}
