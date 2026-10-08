import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/data/run_record_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String session(String owner, String token) => jsonEncode({
  'access_token': token,
  'refresh_token': '테스트용 갱신 토큰',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'user': {
    'id': owner,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-10-08T00:00:00Z',
  },
});

void main() {
  final summary = RunSummary(
    clientRunId: '10000000-0000-0000-0000-000000000001',
    startedAt: DateTime.utc(2026, 10, 8, 6),
    endedAt: DateTime.utc(2026, 10, 8, 7),
    distanceMeters: 5000.4,
    duration: const Duration(minutes: 25),
  );
  final row = {
    'id': '20000000-0000-0000-0000-000000000001',
    'client_run_id': summary.clientRunId,
    'started_at': summary.startedAt.toIso8601String(),
    'ended_at': summary.endedAt.toIso8601String(),
    'distance_m': 5000,
    'duration_sec': 1500,
  };

  test('저장 요청은 소유자와 검증 상태를 전송하지 않습니다', () async {
    late http.Request request;
    final client = SupabaseClient(
      'https://example.supabase.co',
      '테스트용 공개 키',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode(row),
          200,
          request: value,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner', 'token-a'));
    final service = SupabaseRunRecordService(client);
    final saved = await service.save(summary);
    expect(saved.distanceMeters, 5000);
    expect(request.url.path, '/rest/v1/rpc/save_my_run');
    expect(request.headers['authorization'], 'Bearer token-a');
    expect(jsonDecode(request.body), {
      'client_id': summary.clientRunId,
      'start_time': summary.startedAt.toIso8601String(),
      'end_time': summary.endedAt.toIso8601String(),
      'distance_metres': 5000,
      'active_seconds': 1500,
    });
  });

  test('요청 중 계정이 바뀌어도 이전 계정의 인증을 사용하고 결과는 숨깁니다', () async {
    late SupabaseClient client;
    late http.Request request;
    client = SupabaseClient(
      'https://example.supabase.co',
      '테스트용 공개 키',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((value) async {
        request = value;
        await client.auth.recoverSession(session('other-owner', 'token-b'));
        return http.Response(
          jsonEncode(row),
          200,
          request: value,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner', 'token-a'));
    final service = SupabaseRunRecordService(client);
    await expectLater(service.save(summary), throwsA(isA<AuthException>()));
    expect(request.headers['authorization'], 'Bearer token-a');
    await expectLater(service.save(summary), throwsA(isA<AuthException>()));
  });

  test('내 기록만 날짜와 식별자로 정렬하여 페이지 조회합니다', () async {
    late http.Request request;
    final client = SupabaseClient(
      'https://example.supabase.co',
      '테스트용 공개 키',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode([row]),
          200,
          request: value,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(session('owner', 'token-a'));
    final records = await SupabaseRunRecordService(client)
        .list(offset: 20, limit: 20);
    expect(records.single.paceSeconds, 300);
    expect(request.url.queryParameters['user_id'], 'eq.owner');
    expect(
      request.url.queryParameters['order'],
      'started_at.desc.nullslast,id.desc.nullslast',
    );
    expect(request.url.queryParameters['offset'], '20');
    expect(request.url.queryParameters['limit'], '20');
    expect(request.headers['authorization'], 'Bearer token-a');
  });
}
