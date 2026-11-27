import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../firebase_options.dart';
import '../features/settings/data/password_service.dart';
import '../features/auth/data/kakao_sign_in_service.dart';
import '../features/diagnostics/error_reporter.dart';
import '../features/notifications/data/push_service.dart';
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
  // 사진 선택기 정리는 다른 준비와 함께 진행합니다.
  final photoCleanup = discardInterruptedSharePhoto();
  final localConfig = await _loadFallbackConfig();
  final supabaseUrl = _requiredSupabaseUrl(
    _supabaseUrl,
    localConfig['SUPABASE_URL'],
  );
  final supabasePublishableKey = _requiredSupabasePublishableKey(
    _supabasePublishableKey,
    localConfig['SUPABASE_PUBLISHABLE_KEY'],
  );

  PasswordService.configure(supabaseUrl, supabasePublishableKey);
  // 카카오·Firebase·Supabase 준비는 서로 기다릴 필요가 없어 한꺼번에 합니다.
  // 오류 수집(Crashlytics)은 Firebase가 준비된 뒤에 켭니다.
  await Future.wait([
    photoCleanup,
    KakaoSignInService.configure(
      const String.fromEnvironment('KAKAO_NATIVE_KEY').isNotEmpty
          ? const String.fromEnvironment('KAKAO_NATIVE_KEY')
          : localConfig['KAKAO_NATIVE_KEY'] ?? '',
    ),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .then((_) => ErrorReporter.initialize().catchError((_) {})),
    Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    ),
  ]);
  // 푸시는 Firebase와 로그인 정보가 모두 준비된 뒤에 시작합니다.
  PushService.instance.start();
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
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme != 'https' && !(kDebugMode && uri.scheme == 'http'))) {
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
  if (!trimmed.startsWith('sb_publishable_')) {
    Object? claims;
    final parts = trimmed.split('.');
    if (parts.length == 3) {
      try {
        claims = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        );
      } on FormatException {
        // 공개 키 형식이 아니면 앱 시작 전에 거부합니다.
      }
    }
    if (claims is! Map<String, dynamic> || claims['role'] != 'anon') {
      throw const AppStartupException('앱에는 Supabase 공개 키만 설정할 수 있습니다.');
    }
  }
  return trimmed;
}
