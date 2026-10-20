import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/profile/data/run_sharing_preference_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String preferenceSession(String owner, String token) => jsonEncode({
  'access_token': token,
  'refresh_token': '테스트 갱신 토큰',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'user': {
    'id': owner,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-10-20T00:00:00Z',
  },
});

void main() {
  SupabaseClient clientWith(
    Future<http.Response> Function(http.Request) handler,
  ) => SupabaseClient(
    'https://example.supabase.co',
    '테스트 공개 키',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );

  test('설정이 없으면 꺼짐이며 본인 설정만 읽고 저장합니다', () async {
    final requests = <http.Request>[];
    var exists = false;
    var enabled = false;
    final client = clientWith((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map;
        expect(body.keys.toSet(), {'user_id', 'enabled'});
        expect(body['user_id'], 'owner');
        enabled = body['enabled'] as bool;
        exists = true;
      }
      return http.Response(
        jsonEncode(exists ? {'enabled': enabled} : null),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(preferenceSession('owner', 'token-a'));
    final service = SupabaseRunSharingPreferenceService(client);
    expect(await service.load(), isFalse);
    expect(requests.last.url.queryParameters['user_id'], 'eq.owner');
    await service.save(true);
    expect(await service.load(), isTrue);
    await service.save(false);
    expect(await service.load(), isFalse);
    expect(
      requests.every((r) => r.headers['authorization'] == 'Bearer token-a'),
      isTrue,
    );
  });

  test('조회 중 계정이 바뀌면 이전 설정을 반환하거나 새 계정에 저장하지 않습니다', () async {
    var calls = 0;
    late SupabaseClient client;
    client = clientWith((request) async {
      ++calls;
      await client.auth.recoverSession(preferenceSession('other', 'token-b'));
      return http.Response(
        '{"enabled":true}',
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(preferenceSession('owner', 'token-a'));
    final service = SupabaseRunSharingPreferenceService(client);
    await expectLater(service.load(), throwsA(isA<AuthException>()));
    await expectLater(service.save(true), throwsA(isA<AuthException>()));
    expect(calls, 1);
  });

  test('올바르지 않은 설정 응답은 자동 공유 동의로 해석하지 않습니다', () async {
    final client = clientWith(
      (request) async => http.Response(
        '{"enabled":"true"}',
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(preferenceSession('owner', 'token-a'));
    await expectLater(
      SupabaseRunSharingPreferenceService(client).load(),
      throwsFormatException,
    );
  });
}
