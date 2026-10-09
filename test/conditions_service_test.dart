import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/run_conditions/data/conditions_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('서버 요청은 반올림 좌표만 보내고 로그인 세션을 사용합니다', () async {
    late http.Request request;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'fetchedAt': DateTime.now().toIso8601String(),
            'weather': null,
            'dust': null,
            'errors': {},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-user-session',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': '00000000-0000-0000-0000-000000000001',
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-09T00:00:00Z',
        },
      }),
    );
    await SupabaseConditionsService(client).load(37.566512, 126.978234);
    expect(request.url.path, '/functions/v1/running-conditions');
    expect(jsonDecode(request.body), {'latitude': 37.57, 'longitude': 126.98});
    expect(request.headers['authorization'], 'Bearer test-user-session');
    expect(request.body, isNot(contains('SERVICE_KEY')));
  });
  test('서버 실패는 기관 응답 원문 대신 지정된 안내를 표시합니다', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (value) async => http.Response(
          jsonEncode({'error': 'unsupported_area'}),
          422,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabaseConditionsService(client).load(37, -122),
      throwsA(
        isA<ConditionsFailure>().having(
          (value) => value.message,
          '안내',
          contains('지원하지 않습니다'),
        ),
      ),
    );
  });
}
