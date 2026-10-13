import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/run_feedback/data/run_feedback_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String session(String id) => jsonEncode({
  'access_token': 'token-$id',
  'refresh_token': 'refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'user': {
    'id': id,
    'aud': 'authenticated',
    'created_at': '2026-10-13T00:00:00Z',
    'app_metadata': {},
    'user_metadata': {},
  },
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
  test('상태 조회는 본인 세션과 기록 식별자만 전송합니다', () async {
    late http.Request request;
    final client = clientFor((r) async {
      request = r;
      return {'status': 'available'};
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    expect(
      (await SupabaseRunFeedbackService(client).load('run')).status,
      FeedbackStatus.available,
    );
    expect(request.url.path.endsWith('my_run_feedback'), isTrue);
    expect(jsonDecode(request.body), {'requested_run_id': 'run'});
    expect(request.headers['authorization'], 'Bearer token-owner');
  });
  test('생성 요청은 키·좌표·사용자 식별자·기기 측정값을 보내지 않습니다', () async {
    late http.Request request;
    final client = clientFor((r) async {
      request = r;
      return {'status': 'not_configured'};
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    await SupabaseRunFeedbackService(client).generate('run');
    expect(request.url.path.endsWith('/run-feedback'), isTrue);
    expect(jsonDecode(request.body), {'run_id': 'run'});
    expect(request.headers['authorization'], 'Bearer token-owner');
  });
  test('계정 전환 중의 늦은 응답과 이후 요청을 거부합니다', () async {
    final response = Completer<Object>();
    final requested = Completer<void>();
    final client = clientFor((r) {
      if (!requested.isCompleted) requested.complete();
      return response.future;
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner'));
    final service = SupabaseRunFeedbackService(client);
    final loading = service.load('run');
    final expectation = expectLater(loading, throwsA(isA<AuthException>()));
    await requested.future;
    await client.auth.recoverSession(session('other'));
    response.complete({'status': 'available'});
    await expectation;
    expect(service.isCurrentOwner, isFalse);
    await expectLater(service.generate('run'), throwsA(isA<AuthException>()));
  });
  test('로그인하지 않으면 외부 요청을 보내지 않습니다', () async {
    var calls = 0;
    final client = clientFor((r) async {
      calls++;
      return {};
    });
    addTearDown(client.dispose);
    final service = SupabaseRunFeedbackService(client);
    await expectLater(service.load('run'), throwsA(isA<AuthException>()));
    await expectLater(service.generate('run'), throwsA(isA<AuthException>()));
    expect(calls, 0);
  });
}
