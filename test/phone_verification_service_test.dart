import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/auth/data/phone_verification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> owner(String id) => {
  'id': id,
  'aud': 'authenticated',
  'created_at': '2026-10-12T00:00:00Z',
  'app_metadata': <String, Object?>{},
  'user_metadata': {'phone_verified': true},
};
String session(String id) => jsonEncode({
  'access_token': 'token-$id',
  'refresh_token': 'test-refresh-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'user': owner(id),
});

void main() {
  SupabaseClient clientFor(Future<Object> Function(http.Request) handler) =>
      SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(await handler(request)),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
  test('사용자 메타데이터 대신 서버의 전화번호 확인 상태를 읽습니다', () async {
    final client = clientFor(
      (request) async => {
        'verified': false,
        'phone': null,
        'pending_phone': null,
      },
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    expect((await SupabasePhoneVerification(client).load()).verified, isFalse);
  });
  test('이미 인증된 같은 번호는 인증 문자를 다시 보내지 않습니다', () async {
    final requests = <http.Request>[];
    final client = clientFor((request) async {
      requests.add(request);
      return {'verified': true, 'phone': '821012345678', 'pending_phone': null};
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    await SupabasePhoneVerification(client).send('+821012345678');
    expect(requests, hasLength(1));
  });
  test('번호 등록은 서버 Auth에 요청하며 수동 확인 값을 전송하지 않습니다', () async {
    final requests = <http.Request>[];
    final client = clientFor((request) async {
      requests.add(request);
      return request.url.path.endsWith('my_phone_verification_state')
          ? {'verified': false, 'phone': null, 'pending_phone': null}
          : owner('owner');
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    await SupabasePhoneVerification(client).send('+821012345678');
    expect(requests.last.method, 'PUT');
    expect(jsonDecode(requests.last.body), {'phone': '+821012345678'});
  });
  test('인증번호는 가입이 아닌 현재 계정의 번호 변경 유형으로 검증합니다', () async {
    late http.Request request;
    final client = clientFor((r) async {
      request = r;
      return jsonDecode(session('owner'));
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    await SupabasePhoneVerification(client).verify('+821012345678', '123456');
    expect(request.url.path, '/auth/v1/verify');
    final body = jsonDecode(request.body);
    expect(body['type'], 'phone_change');
    expect(body['phone'], '+821012345678');
    expect(body.containsKey('phone_confirm'), isFalse);
  });
  test('계정 전환 뒤 이전 조회 결과와 발송을 사용하지 않습니다', () async {
    late SupabaseClient client;
    final requests = <http.Request>[];
    client = clientFor((r) async {
      requests.add(r);
      await client.auth.recoverSession(session('other'));
      return {'verified': true, 'phone': null, 'pending_phone': null};
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    final service = SupabasePhoneVerification(client);
    await expectLater(service.load(), throwsA(isA<AuthException>()));
    await expectLater(
      service.send('+821012345678'),
      throwsA(isA<AuthException>()),
    );
    expect(requests, hasLength(1));
    expect(requests.single.headers['authorization'], 'Bearer token-owner');
  });

  test('다른 계정으로 검증된 인증 응답은 세션을 폐기하고 거절합니다', () async {
    final requests = <http.Request>[];
    final client = clientFor((r) async {
      requests.add(r);
      return r.url.path.endsWith('/verify')
          ? jsonDecode(session('other'))
          : <String, Object?>{};
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    await expectLater(
      SupabasePhoneVerification(client).verify('+821012345678', '123456'),
      throwsA(isA<AuthException>()),
    );
    expect(client.auth.currentSession, isNull);
    expect(requests.any((r) => r.url.path.endsWith('/logout')), isTrue);
  });
  test('비로그인 상태에서는 조회·발송·코드 검증을 요청하지 않습니다', () async {
    final requests = <http.Request>[];
    final client = clientFor((r) async {
      requests.add(r);
      return <String, Object?>{};
    });
    addTearDown(client.dispose);
    final service = SupabasePhoneVerification(client);
    await expectLater(service.load(), throwsA(isA<AuthException>()));
    await expectLater(
      service.send('+821012345678'),
      throwsA(isA<AuthException>()),
    );
    await expectLater(
      service.verify('+821012345678', '123456'),
      throwsA(isA<AuthException>()),
    );
    expect(requests, isEmpty);
  });
}
