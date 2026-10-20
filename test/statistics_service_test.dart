import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/profile/data/statistics_service.dart';
import 'package:runquest/features/social/data/ranking_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/statistics_fakes.dart';

String session(String owner, String token) => jsonEncode({
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
  for (final ranking in [false, true]) {
    test('${ranking ? '랭킹' : '통계'} 조회는 계정 고정 토큰을 사용하고 집계 응답을 해석합니다', () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        '테스트 공개 키',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(ranking ? rankingJson : statisticsJson),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(session('owner', 'token-a'));
      if (ranking) {
        final result = await SupabaseRankingService(client).load();
        expect(result.entries.first.name, '친구러너');
      } else {
        final result = await SupabaseStatisticsService(client).load();
        expect(result.completedRuns, 23);
      }
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/${ranking ? 'friend_weekly_ranking' : 'my_run_statistics'}',
      );
      expect(requests.single.headers['authorization'], 'Bearer token-a');
      expect(jsonDecode(requests.single.body), isNull);
    });

    test('${ranking ? '랭킹' : '통계'} 조회 중 계정 전환 시 이전 결과와 추가 호출을 차단합니다', () async {
      var calls = 0;
      late SupabaseClient client;
      client = SupabaseClient(
        'https://example.supabase.co',
        '테스트 공개 키',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          ++calls;
          await client.auth.recoverSession(session('other', 'token-b'));
          return http.Response(
            jsonEncode(ranking ? rankingJson : statisticsJson),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.recoverSession(session('owner', 'token-a'));
      final Future<Object> Function() load = ranking
          ? SupabaseRankingService(client).load
          : SupabaseStatisticsService(client).load;
      await expectLater(load(), throwsA(isA<AuthException>()));
      await expectLater(load(), throwsA(isA<AuthException>()));
      expect(calls, 1);
    });
  }
}
