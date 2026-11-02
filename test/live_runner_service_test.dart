import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/home/data/live_runner_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/live_map_fakes.dart';

String _session(String owner) => jsonEncode({
  'access_token': 'test-$owner',
  'refresh_token': 'test-refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'user': {
    'id': owner,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-11-02T00:00:00Z',
  },
});

void main() {
  for (final changeOwner in [false, true]) {
    test(
      '주변 조회는 위치 게시 없이 좌표를 전달하고 계정 전환 응답을 ${changeOwner ? '폐기합니다' : '해석합니다'}',
      () async {
        final requests = <http.Request>[];
        late SupabaseClient client;
        client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            requests.add(request);
            if (changeOwner) {
              await client.auth.recoverSession(_session('other'));
            }
            return http.Response(
              jsonEncode([
                {
                  'user_id': 'runner',
                  'nickname': '이웃러너',
                  'latitude': 37.567,
                  'longitude': 126.978,
                  'distance_m': 55,
                  'updated_at': '2026-11-02T00:00:00Z',
                },
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        addTearDown(client.dispose);
        await client.auth.recoverSession(_session('owner'));
        final service = SupabaseLiveRunnerService(client);
        final future = service.nearby(1000, testFix());
        if (changeOwner) {
          await expectLater(future, throwsA(isA<AuthException>()));
          await expectLater(
            service.nearby(1000, testFix()),
            throwsA(isA<AuthException>()),
          );
        } else {
          expect((await future).single.nickname, '이웃러너');
        }
        expect(requests.single.url.path, '/rest/v1/rpc/map_nearby_runners_at');
        expect(jsonDecode(requests.single.body), {
          'radius_m': 1000,
          'viewer_latitude': 37.5665,
          'viewer_longitude': 126.978,
        });
        expect(requests.single.headers['authorization'], 'Bearer test-owner');
      },
    );
  }
}
