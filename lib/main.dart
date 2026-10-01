import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'app/run_quest_app.dart';

Future<void> main() async {
  try {
    await initializeApp();
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
