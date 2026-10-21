import 'package:supabase_flutter/supabase_flutter.dart';

class BlockedUser {
  const BlockedUser(this.id, this.nickname);
  final String id;
  final String nickname;
}

abstract interface class BlockService {
  bool get isCurrentOwner;
  Future<List<BlockedUser>> load();
  Future<void> change(String userId, {required bool blocked});
}

class SupabaseBlockService implements BlockService {
  SupabaseBlockService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return result;
  }

  @override
  Future<List<BlockedUser>> load() async {
    final rows = await _rpc('my_blocks') as List;
    return rows
        .map(
          (row) =>
              BlockedUser(row['user_id'] as String, row['nickname'] as String),
        )
        .toList();
  }

  @override
  Future<void> change(String userId, {required bool blocked}) async {
    await _rpc('change_my_block', {'target_id': userId, 'blocked': blocked});
  }
}
