import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/app/run_quest_app.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';
import 'package:runquest/features/settings/appearance/appearance_settings_screen.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class _MemoryStore implements AppearanceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// 실제 앱과 같은 방식(테마 선택·글자 크기 적용)으로 화면 설정 화면을 띄웁니다.
Widget app(AppAppearance settings) => ListenableBuilder(
  listenable: settings,
  builder: (context, _) => MaterialApp(
    theme: buildAppTheme(dark: false),
    darkTheme: buildAppTheme(dark: true),
    themeMode: settings.theme.mode,
    themeAnimationDuration: Duration.zero,
    builder: (context, child) =>
        AppearanceScope(textScale: settings.textSize.scale, child: child!),
    home: AppearanceSettingsScreen(appearance: settings),
  ),
);

void main() {
  tearDown(() => AppColors.dark = false);

  test('저장한 화면 설정을 다시 불러오고 모르는 값은 기본값을 씁니다', () async {
    final store = _MemoryStore();
    final first = AppAppearance(store: store);
    await first.setTheme(AppThemeChoice.dark);
    await first.setTextSize(AppTextSize.large);
    final second = AppAppearance(store: store);
    await second.load();
    expect(second.theme, AppThemeChoice.dark);
    expect(second.textSize, AppTextSize.large);

    store.values['appearance.theme'] = 'neon';
    final third = AppAppearance(store: store)..theme = AppThemeChoice.light;
    await third.load();
    expect(third.theme, AppThemeChoice.system);
  });

  testWidgets('다크 모드와 글자 크기를 고르면 바로 앱 전체에 적용됩니다', (tester) async {
    final settings = AppAppearance(store: _MemoryStore());
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(app(settings));
    await tester.pumpAndSettle();
    BuildContext context() => tester.element(find.text('미리보기'));
    expect(Theme.of(context()).brightness, Brightness.light);
    expect(AppColors.dark, isFalse);

    await tester.tap(find.text('다크'));
    await tester.pumpAndSettle();
    expect(settings.theme, AppThemeChoice.dark);
    expect(Theme.of(context()).brightness, Brightness.dark);
    expect(AppColors.dark, isTrue);
    expect(AppColors.surface, isNot(Colors.white));

    // 기기 설정을 고르면 휴대폰의 밝기를 따릅니다.
    await tester.tap(find.text('기기 설정'));
    await tester.pumpAndSettle();
    expect(Theme.of(context()).brightness, Brightness.light);
    expect(AppColors.dark, isFalse);

    expect(MediaQuery.textScalerOf(context()).scale(10), 10);
    await tester.tap(find.text('아주 크게'));
    await tester.pumpAndSettle();
    expect(settings.textSize, AppTextSize.extraLarge);
    expect(MediaQuery.textScalerOf(context()).scale(10), closeTo(13, .01));
    expect(tester.takeException(), isNull);
  });
}
