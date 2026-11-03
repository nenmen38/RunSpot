import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/settings/data/password_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late PasswordService service;
  final requests = <http.Request>[];
  var correctPassword = true;
  final owner = {
    'id': 'owner',
    'aud': 'authenticated',
    'email': 'runner@example.com',
    'created_at': '2026-01-01T00:00:00Z',
    'identities': [
      {'id': 'email', 'user_id': 'owner', 'provider': 'email'},
    ],
  };
  setUp(() async {
    requests.clear();
    correctPassword = true;
    client = SupabaseClient(
      'https://example.supabase.co',
      'public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(owner),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'session',
        'refresh_token': 'refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': owner,
      }),
    );
    service = PasswordService(
      client,
      verificationClientFactory: () => SupabaseClient(
        'https://example.supabase.co',
        'public-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final login = request.url.path.endsWith('/token');
          if (login && !correctPassword) {
            return http.Response(
              jsonEncode({
                'error_code': 'invalid_credentials',
                'msg': 'Invalid login credentials',
              }),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            login
                ? jsonEncode({
                    'access_token': 'verification-session',
                    'refresh_token': 'verification-refresh',
                    'token_type': 'bearer',
                    'expires_in': 3600,
                    'user': owner,
                  })
                : '{}',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      ),
    );
  });
  tearDown(() => client.dispose());
  test('별도 세션에서 현재 비밀번호 검증 후 기존 계정의 비밀번호를 변경합니다', () async {
    await service.change('Oldpass1!', 'Newpass2!');
    expect(requests.map((r) => r.method), ['POST', 'POST', 'PUT']);
    expect(client.auth.currentSession!.accessToken, 'session');
    final body = jsonDecode(requests.last.body);
    expect(body['current_password'], 'Oldpass1!');
    expect(body['password'], 'Newpass2!');
  });
  test('현재 비밀번호가 틀리면 새 비밀번호 변경 요청을 보내지 않습니다', () async {
    correctPassword = false;
    await expectLater(
      service.change('Wrongpass1!', 'Newpass2!'),
      throwsA(isA<AuthException>()),
    );
    expect(requests.where((r) => r.method == 'PUT'), isEmpty);
    expect(client.auth.currentSession!.accessToken, 'session');
  });
  test('작성 규칙 위반과 같은 비밀번호는 서버에 전송하지 않습니다', () async {
    await expectLater(
      service.change('Oldpass1!', 'weak'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      service.change('Oldpass1!', 'Oldpass1!'),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
  });
  test('로그아웃된 계정으로 비밀번호를 변경하지 않습니다', () async {
    await client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    await expectLater(
      service.change('Oldpass1!', 'Newpass2!'),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
  });
}
