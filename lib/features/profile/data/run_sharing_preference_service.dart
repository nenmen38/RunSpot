import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class RunSharingPreferenceService {
  bool get isCurrentOwner;
  Future<bool> load();
  Future<void> save(bool enabled);
}

/// 러닝 자동 공유 설정만 저장하며 공개 범위와 인증 상태는 변경하지 않습니다.
class SupabaseRunSharingPreferenceService
    implements RunSharingPreferenceService {
  SupabaseRunSharingPreferenceService(this.client)
    : _owner = client.auth.currentUser?.id;

  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Session _session() {
    if (!isCurrentOwner) throw const AuthException('로그인 상태를 확인해 주세요.');
    return client.auth.currentSession!;
  }

  @override
  Future<bool> load() async {
    final session = _session();
    final row = await client
        .from('run_location_preferences')
        .select('enabled')
        .eq('user_id', _owner!)
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .maybeSingle();
    _session();
    if (row == null) return false;
    final value = row['enabled'];
    if (value is! bool) throw const FormatException('위치 공유 설정 응답이 올바르지 않습니다.');
    return value;
  }

  @override
  Future<void> save(bool enabled) async {
    final session = _session();
    final row = await client
        .from('run_location_preferences')
        .upsert({'user_id': _owner!, 'enabled': enabled})
        .select('enabled')
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .single();
    _session();
    if (row['enabled'] != enabled) {
      throw const FormatException('위치 공유 설정이 저장되지 않았습니다.');
    }
  }
}
