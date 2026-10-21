import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/features/social/data/block_service.dart';
import 'package:runquest/features/social/blocked_users_screen.dart';
import 'package:runquest/features/social/widgets/block_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _session(String owner, String token) => jsonEncode({
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
    'created_at': '2026-10-21T00:00:00Z',
  },
});

class _Blocks implements BlockService {
  bool current = true;
  bool fail = false;
  final changes = <bool>[];
  final users = <BlockedUser>[const BlockedUser('runner', '친구러너')];
  Completer<void>? pending;
  @override
  bool get isCurrentOwner => current;
  @override
  Future<List<BlockedUser>> load() async => List.of(users);
  @override
  Future<void> change(String userId, {required bool blocked}) async {
    changes.add(blocked);
    if (fail) throw StateError('연결 실패');
    await pending?.future;
    if (!blocked) users.removeWhere((user) => user.id == userId);
  }
}

void main() {
  test('차단 조회·변경은 계정 고정 토큰과 서버 계약을 사용합니다', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      '테스트 공개 키',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          request.url.path.endsWith('my_blocks')
              ? '[{"user_id":"runner","nickname":"친구러너"}]'
              : 'null',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(_session('owner', 'token-a'));
    final service = SupabaseBlockService(client);
    expect((await service.load()).single.nickname, '친구러너');
    await service.change('runner', blocked: true);
    await service.change('runner', blocked: false);
    expect(
      requests.every(
        (request) => request.headers['authorization'] == 'Bearer token-a',
      ),
      isTrue,
    );
    expect(jsonDecode(requests[1].body), {
      'target_id': 'runner',
      'blocked': true,
    });
    expect(jsonDecode(requests[2].body), {
      'target_id': 'runner',
      'blocked': false,
    });
    await client.auth.recoverSession(_session('other', 'token-b'));
    await expectLater(service.load(), throwsA(isA<AuthException>()));
    await expectLater(
      service.change('runner', blocked: true),
      throwsA(isA<AuthException>()),
    );
    expect(requests, hasLength(3));
  });

  test('조회 도중 계정이 변경되면 이전 계정의 목록을 폐기합니다', () async {
    late SupabaseClient client;
    client = SupabaseClient(
      'https://example.supabase.co',
      '테스트 공개 키',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        await client.auth.recoverSession(_session('other', 'token-b'));
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.auth.recoverSession(_session('owner', 'token-a'));
    await expectLater(
      SupabaseBlockService(client).load(),
      throwsA(isA<AuthException>()),
    );
  });

  testWidgets('차단 확인 취소는 요청하지 않고 실패는 재시도할 수 있습니다', (tester) async {
    final service = _Blocks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockButton(
            service: service,
            userId: 'runner',
            nickname: '친구러너',
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('사용자 차단'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(service.changes, isEmpty);
    service.fail = true;
    await tester.tap(find.byTooltip('사용자 차단'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('차단'));
    await tester.pumpAndSettle();
    expect(find.text('차단 설정을 변경하지 못했습니다. 다시 시도해 주세요.'), findsOneWidget);
    expect(service.changes, [true]);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('차단 목록에서 해제하면 서버를 다시 조회하고 목록에서 제거합니다', (tester) async {
    final service = _Blocks();
    await tester.pumpWidget(
      MaterialApp(home: BlockedUsersScreen(service: service)),
    );
    await tester.pumpAndSettle();
    expect(find.text('친구러너'), findsOneWidget);
    await tester.tap(find.byTooltip('차단 해제'));
    await tester.pumpAndSettle();
    expect(find.textContaining('친구 관계는 복원되지 않습니다.'), findsOneWidget);
    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();
    expect(service.changes, [false]);
    expect(find.text('차단한 사용자가 없습니다.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('처리 중 중복 요청을 막고 계정 전환 뒤 갱신하지 않습니다', (tester) async {
    final service = _Blocks()..pending = Completer<void>();
    var changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlockButton(
            service: service,
            userId: 'runner',
            nickname: '친구러너',
            onChanged: () => changed++,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('사용자 차단'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('차단'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNull,
    );
    service.current = false;
    service.pending!.complete();
    await tester.pumpAndSettle();
    expect(changed, 0);
    expect(service.changes, [true]);
  });
}
