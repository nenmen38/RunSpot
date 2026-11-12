import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/crew.dart';

abstract interface class CrewService {
  bool get isCurrentOwner;
  Future<CrewDashboard> load();
  Future<CrewDashboard> create(String name, String description, CrewIcon icon);

  /// [crewId] 크루로 친구를 초대합니다. 그 크루의 크루장만 할 수 있습니다.
  Future<CrewDashboard> invite(String userId, String crewId);
  Future<CrewDashboard> respond(String crewId, {required bool accept});
}

class SupabaseCrewService implements CrewService {
  SupabaseCrewService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Future<CrewDashboard> _rpc(
    String name, [
    Map<String, dynamic>? params,
  ]) async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return CrewDashboard.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<CrewDashboard> load() => _rpc('my_crew');

  @override
  Future<CrewDashboard> create(
    String name,
    String description,
    CrewIcon icon,
  ) => _rpc('create_crew', {
    'requested_name': name,
    'requested_description': description,
    'requested_icon': icon.code,
  });

  @override
  Future<CrewDashboard> invite(String userId, String crewId) =>
      _rpc('invite_to_crew', {'target': userId, 'requested_crew': crewId});

  @override
  Future<CrewDashboard> respond(String crewId, {required bool accept}) =>
      _rpc('respond_crew_invite', {'requested_crew': crewId, 'accept': accept});
}
