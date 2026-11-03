import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:supabase_flutter/supabase_flutter.dart';

class KakaoSignInService {
  KakaoSignInService(this.client, {this.requestToken});

  final SupabaseClient client;
  final Future<kakao.OAuthToken> Function(String nonce)? requestToken;
  static bool _configured = false;

  static Future<void> configure(String nativeAppKey) async {
    if (nativeAppKey.trim().isEmpty) return;
    await kakao.KakaoSdk.init(
      nativeAppKey: nativeAppKey.trim(),
      loggingEnabled: false,
    );
    _configured = true;
  }

  Future<void> signIn() async {
    if (!_configured && requestToken == null) {
      throw const AuthException('카카오 로그인 설정을 확인해 주세요.');
    }
    final random = Random.secure();
    final nonce = base64UrlEncode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final hashedNonce = sha256.convert(utf8.encode(nonce)).toString();
    kakao.OAuthToken token;
    try {
      // 이메일 권한을 추가 요청하지 않고 카카오 앱에 등록된 동의항목만 사용합니다.
      token =
          await (requestToken?.call(hashedNonce) ??
              kakao.UserApi.instance.loginWithKakaoAccount(nonce: hashedNonce));
    } on kakao.KakaoClientException catch (error) {
      if (error.reason == kakao.ClientErrorCause.cancelled) return;
      throw const AuthException('카카오 로그인에 실패했습니다. 다시 시도해 주세요.');
    }
    try {
      final idToken = token.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const AuthException('카카오 OpenID Connect 설정을 확인해 주세요.');
      }
      // 고유 ID·서명·발급 대상·nonce는 Supabase 인증 서버에서 검증합니다.
      await client.auth.signInWithIdToken(
        provider: OAuthProvider.kakao,
        idToken: idToken,
        accessToken: token.accessToken,
        nonce: nonce,
      );
    } finally {
      // 앱에서는 Supabase 세션만 유지합니다.
      if (requestToken == null) {
        await kakao.TokenManagerProvider.instance.manager.clear();
      }
    }
  }
}
