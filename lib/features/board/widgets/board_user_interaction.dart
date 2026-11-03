import 'package:flutter/material.dart';

import '../../social/data/friend_service.dart';
import '../../social/widgets/user_interaction_sheet.dart';
import '../data/board_interaction_service.dart';
import '../data/board_service.dart';

Future<bool> showBoardUserInteraction(
  BuildContext context, {
  required BoardService service,
  required String postId,
  String? commentId,
}) async {
  if (service is! SupabaseBoardService || !service.isCurrentOwner) return false;
  final blocks = BoardInteractionService(
    service.client,
    postId,
    commentId: commentId,
  );
  try {
    final author = await blocks.author();
    if (!context.mounted || !service.isCurrentOwner) return false;
    final id = author['user_id'] as String;
    if (id == service.client.auth.currentUser?.id) return false;
    return await showUserInteraction(
      context,
      userId: id,
      nickname: author['nickname'] as String,
      blocks: blocks,
      friends: SupabaseFriendService(service.client),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자 정보를 불러오지 못했습니다. 다시 시도해 주세요.')),
      );
    }
    return false;
  }
}
