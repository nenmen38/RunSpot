import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/auth/data/email_verification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/auth_storage.dart';

Map<String, Object?> user({
  String id = 'owner',
  String? email = 'runner@example.com',
  String? pendingEmail,
}) => {
  'id': id,
  'aud': 'authenticated',
  'app_metadata': <String, Object?>{},
  'user_metadata': {'email_verified': true},
  'created_at': '2026-10-09T00:00:00Z',
  'email': email,
  'email_confirmed_at': '2026-10-09T00:00:00Z',
  'new_email': pendingEmail,
};

String session(String owner) => jsonEncode({
  'access_token': 'token-$owner',
  'refresh_token': '테스트용 갱신 토큰',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'user': user(id: owner),
});

void main() {
  SupabaseClient clientFor(
    Future<http.Response> Function(http.Request) handler,
  ) => SupabaseClient(
    'https://example.supabase.co',
    '테스트용 공개 키',
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: MemoryAuthStorage(),
    ),
    httpClient: MockClient((request) async {
      final result = await handler(request);
      return http.Response.bytes(
        result.bodyBytes,
        result.statusCode,
        headers: result.headers,
        request: request,
      );
    }),
  );
  http.Response response(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  test('메타데이터와 기존 사용자 확인 시각 대신 서버 인증 상태를 사용합니다', () async {
    final client = clientFor(
      (request) async => response(
        request.url.path.endsWith('my_email_verified') ? false : user(),
      ),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    final state = await SupabaseEmailVerification(client).load();
    expect(state.verified, isFalse);
    expect(state.confirmationEmail, 'runner@example.com');
  });

  for (final pending in [null, 'next@example.com']) {
    test(
      '기존 ${pending == null ? "가입" : "이메일 변경"} 메일은 올바른 유형으로 재전송합니다',
      () async {
        final requests = <http.Request>[];
        final client = clientFor((request) async {
          requests.add(request);
          if (request.url.path.endsWith('my_email_verified')) {
            return response(false);
          }
          if (request.url.path.endsWith('/resend')) {
            return response(<String, Object?>{});
          }
          return response(user(pendingEmail: pending));
        });
        addTearDown(client.dispose);
        await client.auth.recoverSession(session('owner'));
        await SupabaseEmailVerification(client)
            .send(pending ?? 'runner@example.com');
        final sent = requests.last;
        expect(sent.url.path, '/auth/v1/resend');
        expect(
          jsonDecode(sent.body)['type'],
          pending == null ? 'signup' : 'email_change',
        );
        expect(jsonDecode(sent.body)['email'], 'runner@example.com');
        expect(
          sent.url.queryParameters['redirect_to'],
          'runspot://login-callback',
        );
        expect(
          requests.any((r) {
            final body = jsonDecode(r.body.isEmpty ? '{}' : r.body);
            return body is Map && body.containsKey('phone');
          }),
          isFalse,
        );
      },
    );
  }

  for (final pending in [null, 'new@example.com']) {
    test('기존 이메일이 없는 계정은 이메일 등록 요청으로 발송·재전송합니다 ($pending)', () async {
      final requests = <http.Request>[];
      final client = clientFor((request) async {
        requests.add(request);
        if (request.url.path.endsWith('my_email_verified')) {
          return response(false);
        }
        return response(user(email: null, pendingEmail: pending));
      });
      addTearDown(client.dispose);
      await client.auth.recoverSession(session('owner'));
      await SupabaseEmailVerification(client).send('new@example.com');
      expect(requests.last.method, 'PUT');
      final body = jsonDecode(requests.last.body);
      expect(body['email'], 'new@example.com');
      expect(body['code_challenge'], isNotEmpty);
      expect(body['code_challenge_method'], 's256');
    });
  }

  test('이미 이메일 인증된 계정은 발송 요청을 하지 않습니다', () async {
    final requests = <http.Request>[];
    final client = clientFor((request) async {
      requests.add(request);
      return response(
        request.url.path.endsWith('my_email_verified') ? true : user(),
      );
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    await SupabaseEmailVerification(client).send('runner@example.com');
    expect(
      requests.any(
        (r) => r.method != 'GET' && !r.url.path.endsWith('my_email_verified'),
      ),
      isFalse,
    );
  });

  test('계정 전환 뒤 이전 인증 응답을 사용하거나 메일을 보내지 않습니다', () async {
    late SupabaseClient client;
    final requests = <http.Request>[];
    client = clientFor((request) async {
      requests.add(request);
      await client.auth.recoverSession(session('other'));
      return response(user());
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    final service = SupabaseEmailVerification(client);
    await expectLater(service.load(), throwsA(isA<AuthException>()));
    await expectLater(
      service.send('runner@example.com'),
      throwsA(isA<AuthException>()),
    );
    expect(requests, hasLength(1));
    expect(requests.single.headers['authorization'], 'Bearer token-owner');
  });

  test('비로그인 상태에서는 외부 요청 없이 거부합니다', () async {
    final requests = <http.Request>[];
    final client = clientFor((request) async {
      requests.add(request);
      return response(false);
    });
    addTearDown(client.dispose);
    await expectLater(
      SupabaseEmailVerification(client).isVerified(),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
  });
}
