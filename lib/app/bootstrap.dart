import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';
import '../features/run_share/data/share_photo_service.dart';
import 'local_config_loader.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

class AppStartupException implements Exception {
  const AppStartupException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<void> initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await discardInterruptedSharePhoto();
  final localConfig = await _loadFallbackConfig();
  final supabaseUrl = _requiredSupabaseUrl(
    _supabaseUrl,
    localConfig['SUPABASE_URL'],
  );
  final supabasePublishableKey = _requiredSupabasePublishableKey(
    _supabasePublishableKey,
    localConfig['SUPABASE_PUBLISHABLE_KEY'],
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  await _configureFirebaseMessagingForDebug();
}

Future<Map<String, String>> _loadFallbackConfig() async {
  if (!kDebugMode ||
      (_supabaseUrl.trim().isNotEmpty &&
          _supabasePublishableKey.trim().isNotEmpty)) {
    return const {};
  }
  return loadLocalDevConfig();
}

String _requiredSupabaseUrl(String value, String? fallback) {
  final trimmed = value.trim().isNotEmpty
      ? value.trim()
      : fallback?.trim() ?? '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw const AppStartupException(
      'Supabase URL 설정이 필요합니다. config/dev.json 값을 확인하거나 --dart-define-from-file=config/dev.json으로 앱을 다시 실행해 주세요.',
    );
  }
  return trimmed;
}

String _requiredSupabasePublishableKey(String value, String? fallback) {
  final trimmed = value.trim().isNotEmpty
      ? value.trim()
      : fallback?.trim() ?? '';
  if (trimmed.isEmpty) {
    throw const AppStartupException(
      'Supabase 공개 키 설정이 필요합니다. config/dev.json 값을 확인하거나 --dart-define-from-file=config/dev.json으로 앱을 다시 실행해 주세요.',
    );
  }
  return trimmed;
}

Future<void> _configureFirebaseMessagingForDebug() async {
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission();

  if (!kDebugMode) {
    return;
  }

  try {
    final token = await messaging.getToken();
    // ignore: prefer_interpolation_to_compose_strings
    debugPrint('FCM token: ' + (token ?? 'null'));

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      // ignore: prefer_interpolation_to_compose_strings
      debugPrint('FCM token refreshed: ' + token);
    });
  } catch (error) {
    // ignore: prefer_interpolation_to_compose_strings
    debugPrint('FCM token error: ' + error.toString());
  }
}
