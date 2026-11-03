import 'package:supabase_flutter/supabase_flutter.dart';

import '../../social/data/block_service.dart';

class BoardInteractionService extends SupabaseBlockService {
  BoardInteractionService(super.client, this.postId, {this.commentId});
  final String postId;
  final String? commentId;
  Future<Map<String, dynamic>> author() => _request('view');
  Future<Map<String, dynamic>> _request(String operation) async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(
          'board_user_interaction',
          params: {
            'target_post': postId,
            'target_comment': commentId,
            'operation': operation,
          },
        )
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<void> change(String userId, {required bool blocked}) async {
    if (blocked) {
      await _request('block');
    } else {
      await super.change(userId, blocked: false);
    }
  }
}
