import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/social/data/friend_service.dart';
import 'package:runquest/features/social/models/friend_entry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _session(String owner, String token) => jsonEncode({
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
    'created_at': '2026-10-09T00:00:00Z',
  },
});

void main() {
  final row = {
    'user_id': 'target',
    'nickname': '러너',
    'relation': 'received',
    'relationship_id': 'connection',
    'created_at': '2026-10-09T00:00:00Z',
  };
  SupabaseClient mockClient(
    Future<http.Response> Function(http.Request) handler,
  ) => SupabaseClient(
    'https://example.supabase.co',
    '테스트용 공개 키',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handler),
  );

  test('서버 목록과 정확한 닉네임 검색 결과를 해석합니다', () async {
    final requests = <http.Request>[];
    final client = mockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(
          request.url.path.endsWith('friend_dashboard')
              ? {
                  'can_interact': true,
                  'entries': [row],
                }
              : [row],
        ),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(_session('owner', 'token-a'));
    final service = SupabaseFriendService(client);
    final dashboard = await service.load();
    final found = await service.search('러너');
    expect(dashboard.canInteract, isTrue);
    expect(dashboard.entries.single.relation, FriendRelation.received);
    expect(found.single.relationshipId, 'connection');
    expect(requests.first.url.path, '/rest/v1/rpc/friend_dashboard');
    expect(jsonDecode(requests.last.body), {'requested_nickname': '러너'});
    expect(
      requests.every(
        (request) => request.headers['authorization'] == 'Bearer token-a',
      ),
      isTrue,
    );
  });

  test('친구 변경은 대상과 동작 및 확인한 관계 식별자만 전송합니다', () async {
    final requests = <http.Request>[];
    final client = mockClient((request) async {
      requests.add(request);
      return http.Response('', 204, request: request);
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(_session('owner', 'token-a'));
    final service = SupabaseFriendService(client);
    final entry = FriendEntry.fromJson(row);
    await service.change(entry, FriendAction.accept);
    await service.change(entry, FriendAction.request);
    expect(requests.first.url.path, '/rest/v1/rpc/change_friend');
    expect(jsonDecode(requests.first.body), {
      'target_id': 'target',
      'operation': 'accept',
      'expected_id': 'connection',
    });
    expect(jsonDecode(requests.last.body), {
      'target_id': 'target',
      'operation': 'request',
      'expected_id': null,
    });
  });

  test('계정이 바뀌어도 이전 세션으로 전송하고 이전 결과는 노출하지 않습니다', () async {
    late SupabaseClient client;
    final requests = <http.Request>[];
    client = mockClient((request) async {
      requests.add(request);
      await client.auth.recoverSession(_session('other', 'token-b'));
      return http.Response(
        jsonEncode({
          'can_interact': true,
          'entries': [row],
        }),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.dispose);
    await client.auth.recoverSession(_session('owner', 'token-a'));
    final service = SupabaseFriendService(client);
    await expectLater(service.load(), throwsA(isA<AuthException>()));
    expect(requests.single.headers['authorization'], 'Bearer token-a');
    await expectLater(service.search('러너'), throwsA(isA<AuthException>()));
    await expectLater(
      service.change(FriendEntry.fromJson(row), FriendAction.accept),
      throwsA(isA<AuthException>()),
    );
    expect(requests, hasLength(1));
  });
}
