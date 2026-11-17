import 'package:supabase_flutter/supabase_flutter.dart';

class AccountRpc {
  AccountRpc(this.client) : owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? owner;

  Future<dynamic> call(String method, Map<String, dynamic> params) async {
    final session = client.auth.currentSession;
    if (session == null || session.user.id != owner) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    final result = await client
        .rpc(method, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (client.auth.currentUser?.id != owner) {
      throw const AuthException('계정이 변경되었습니다.');
    }
    return result;
  }
}
