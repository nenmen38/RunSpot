import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/running_group.dart';

abstract interface class GroupService {
  String get ownerId;
  bool get isCurrentOwner;
  Future<GroupDashboard> load();
  Future<String> change(
    String operation, {
    String? groupId,
    String? targetId,
    String? clientId,
  });
}

class SupabaseGroupService implements GroupService {
  SupabaseGroupService(this.client)
    : ownerId =
          client.auth.currentUser?.id ??
          (throw const AuthException('로그인이 필요합니다.'));
  final SupabaseClient client;
  @override
  final String ownerId;
  @override
  bool get isCurrentOwner => client.auth.currentSession?.user.id == ownerId;
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
  Future<GroupDashboard> load() async => GroupDashboard.fromJson(
    Map<String, dynamic>.from(await _rpc('group_dashboard') as Map),
  );
  @override
  Future<String> change(
    String operation, {
    String? groupId,
    String? targetId,
    String? clientId,
  }) async => await _rpc('group_action', {
    'requested_group': groupId,
    'operation': operation,
    'target_id': targetId,
    'client_id': clientId,
  }) as String;
}
