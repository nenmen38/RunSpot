import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:runquest/features/auth/data/kakao_sign_in_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('이메일 없이 카카오 ID 토큰과 nonce를 서버에 전달합니다', () async {
    Map<String, dynamic>? body;
    String? requestedNonce;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'access_token': 'session-token',
            'refresh_token': 'refresh-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'owner',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00Z',
              'app_metadata': {'provider': 'kakao'},
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final service = KakaoSignInService(
      client,
      requestToken: (nonce) async {
        requestedNonce = nonce;
        return kakao.OAuthToken('kakao-access', DateTime.now(), null, null, [
          'profile_nickname',
        ], idToken: 'signed-kakao-id-token');
      },
    );
    await service.signIn();
    expect(body!['provider'], 'kakao');
    expect(body!['id_token'], 'signed-kakao-id-token');
    expect(body!['access_token'], 'kakao-access');
    expect(
      requestedNonce,
      sha256.convert(utf8.encode(body!['nonce'] as String)).toString(),
    );
    expect(body!.containsKey('email'), isFalse);
    expect(client.auth.currentUser!.id, 'owner');
  });

  test('ID 토큰이 없으면 계정을 만들지 않습니다', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    final service = KakaoSignInService(
      client,
      requestToken: (_) async =>
          kakao.OAuthToken('access', DateTime.now(), null, null, []),
    );
    await expectLater(service.signIn(), throwsA(isA<AuthException>()));
    expect(calls, 0);
  });
}
