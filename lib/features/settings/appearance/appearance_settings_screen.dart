import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import 'app_appearance.dart';

/// 설정 → 화면: 다크·라이트 모드와 글자 크기를 고릅니다. 고르는 즉시 앱 전체에 적용됩니다.
class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({this.appearance, super.key});

  final AppAppearance? appearance;

  @override
  Widget build(BuildContext context) {
    final settings = appearance ?? AppAppearance.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('화면')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final text = Theme.of(context).textTheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('화면 모드', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('기기 설정을 고르면 휴대폰의 다크 모드 설정을 따라갑니다.', style: text.bodySmall),
              const SizedBox(height: 12),
              SegmentedButton<AppThemeChoice>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AppThemeChoice.system,
                    icon: Icon(Icons.brightness_auto_outlined),
                    label: Text('기기 설정'),
                  ),
                  ButtonSegment(
                    value: AppThemeChoice.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('라이트'),
                  ),
                  ButtonSegment(
                    value: AppThemeChoice.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('다크'),
                  ),
                ],
                selected: {settings.theme},
                onSelectionChanged: (value) => settings.setTheme(value.single),
              ),
              const SizedBox(height: 32),
              Text('글자 크기', style: text.titleMedium),
              const SizedBox(height: 4),
              Text('휴대폰의 글자 크기 설정에 더해 적용됩니다.', style: text.bodySmall),
              const SizedBox(height: 12),
              SegmentedButton<AppTextSize>(
                showSelectedIcon: false,
                segments: [
                  for (final size in AppTextSize.values)
                    ButtonSegment(value: size, label: Text(size.label)),
                ],
                selected: {settings.textSize},
                onSelectionChanged: (value) =>
                    settings.setTextSize(value.single),
              ),
              const SizedBox(height: 16),
              // 고른 크기가 어떻게 보이는지 바로 확인합니다.
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('미리보기', style: text.labelLarge),
                      const SizedBox(height: 8),
                      Text('오늘 한강에서 5km 달렸어요.', style: text.titleMedium),
                      const SizedBox(height: 4),
                      Text('평균 페이스 5\'30" · 28분 10초', style: text.bodyMedium),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // 앱 언어: 기기 설정·한국어·English(일부 화면부터 번역).
              Text(context.l10n.languageTitle, style: text.titleMedium),
              const SizedBox(height: 4),
              Text(context.l10n.languageHint, style: text.bodySmall),
              const SizedBox(height: 12),
              SegmentedButton<AppLanguage>(
                key: const ValueKey('language-choice'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AppLanguage.system,
                    icon: const Icon(Icons.language),
                    label: Text(context.l10n.languageSystem),
                  ),
                  ButtonSegment(
                    value: AppLanguage.korean,
                    label: Text(context.l10n.languageKorean),
                  ),
                  ButtonSegment(
                    value: AppLanguage.english,
                    label: Text(context.l10n.languageEnglish),
                  ),
                ],
                selected: {settings.language},
                onSelectionChanged: (value) =>
                    settings.setLanguage(value.single),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 설정 목록에 보여줄 현재 선택 요약입니다. 예: "다크 · 글자 크게"
String appearanceSummary(AppAppearance settings) =>
    '${settings.theme.label} · 글자 ${settings.textSize.label}';
