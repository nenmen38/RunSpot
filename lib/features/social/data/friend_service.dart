import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/friend_entry.dart';

abstract interface class FriendService {
  bool get isCurrentOwner;
  Future<FriendDashboard> load();
  Future<List<FriendEntry>> search(String nickname);
  Future<void> change(FriendEntry entry, FriendAction action);
}

class SupabaseFriendService implements FriendService {
  SupabaseFriendService(this.client)
    : _ownerId =
          client.auth.currentUser?.id ??
          (throw const AuthException('로그인이 필요합니다.'));

  final SupabaseClient client;
  final String _ownerId;

  @override
  bool get isCurrentOwner => client.auth.currentSession?.user.id == _ownerId;

  Session _requireOwner() {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != _ownerId) {
      throw const AuthException('로그인이 필요합니다.');
    }
    return session;
  }

  Future<dynamic> _rpc(String function, {Map<String, dynamic>? params}) async {
    final session = _requireOwner();
    // 계정 전환 중에도 최초 계정의 세션으로만 요청을 보냅니다.
    final result = await client
        .rpc(function, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _requireOwner();
    return result;
  }

  @override
  Future<FriendDashboard> load() async => FriendDashboard.fromJson(
    Map<String, dynamic>.from(await _rpc('friend_dashboard') as Map),
  );

  @override
  Future<List<FriendEntry>> search(String nickname) async {
    final rows = await _rpc(
      'search_friend',
      params: {'requested_nickname': nickname},
    ) as List;
    return rows
        .map(
          (row) => FriendEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
  }

  @override
  Future<void> change(FriendEntry entry, FriendAction action) async {
    await _rpc(
      'change_friend',
      params: {
        'target_id': entry.userId,
        'operation': action.name,
        'expected_id': action == FriendAction.request
            ? null
            : entry.relationshipId,
      },
    );
  }
}
