import 'package:flutter/material.dart';
import 'package:runquest/features/settings/run_auto_pause_settings.dart';

import 'app/bootstrap.dart';
import 'features/onboarding/app_tour.dart';
import 'shared/widgets/brand_intro.dart';
import 'app/run_quest_app.dart';
import 'features/settings/appearance/app_appearance.dart';
import 'features/settings/body_weight.dart';
import 'features/settings/run_voice_settings.dart';

Future<void> main() async {
  try {
    await initializeApp();
    // 다크 모드·글자 크기 설정을 먼저 불러와 첫 화면부터 반영합니다.
    await AppAppearance.instance.load();
    await RunVoiceSettings.instance.load();
    await RunAutoPauseSettings.instance.load();
    await BrandIntro.preload();
    await BodyWeight.instance.load();
    await AppTour.instance.load();
    runApp(const RunQuestApp());
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'bootstrap',
      ),
    );
    runApp(
      StartupErrorApp(
        message: error is AppStartupException
            ? error.message
            : '앱을 시작하지 못했습니다. 설정을 확인해 주세요.',
      ),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '앱 설정 오류',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message),
                const SizedBox(height: 12),
                const SelectableText(
                  'config/dev.json 확인\n'
                  'flutter run --dart-define-from-file=config/dev.json',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
