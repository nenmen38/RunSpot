import 'package:flutter/material.dart';
import 'package:runquest/features/settings/run_auto_pause_settings.dart';

import 'app/bootstrap.dart';
import 'features/onboarding/app_tour.dart';
import 'shared/widgets/brand_intro.dart';
import 'app/run_quest_app.dart';
import 'features/settings/appearance/app_appearance.dart';
import 'features/settings/body_weight.dart';
import 'features/settings/location_privacy.dart';
import 'features/settings/run_voice_settings.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    // 서로 관계없는 준비를 한꺼번에 해서 첫 화면을 빨리 띄웁니다.
    // 다크 모드·글자 크기 설정도 여기서 불러와 첫 화면부터 반영합니다.
    await Future.wait([
      initializeApp(),
      AppAppearance.instance.load(),
      RunVoiceSettings.instance.load(),
      RunAutoPauseSettings.instance.load(),
      BrandIntro.preload(),
      BodyWeight.instance.load(),
      AppTour.instance.load(),
      LocationPrivacy.instance.load(),
    ]);
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
