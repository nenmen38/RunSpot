import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/board_post.dart';

abstract interface class BoardService {
  bool get isCurrentOwner;
  Future<BoardFeed> load(
    BoardKind kind, {
    BoardTopic? topic,
    BoardCursor? before,
  });
  Future<String> setRegion(String region);
  Future<String> create(BoardDraft draft);
  Future<void> delete(String postId);
}

class SupabaseBoardService implements BoardService {
  SupabaseBoardService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return result;
  }

  @override
  Future<BoardFeed> load(
    BoardKind kind, {
    BoardTopic? topic,
    BoardCursor? before,
  }) async => BoardFeed.fromJson(
    Map<String, dynamic>.from(
      await _rpc('board_feed', {
        'requested_board': kind.code,
        'requested_topic': topic?.code,
        'before_at': before?.at,
        'before_id': before?.id,
      }) as Map,
    ),
  );

  @override
  Future<String> setRegion(String region) async =>
      await _rpc('set_my_board_region', {'requested_region': region}) as String;

  @override
  Future<String> create(BoardDraft draft) async => await _rpc(
    'create_board_post',
    {
      'client_id': draft.clientId,
      'requested_board': draft.kind.code,
      'requested_title': draft.title,
      'requested_body': draft.body,
      'requested_topic': draft.topic?.code,
      'requested_race_date': draft.raceDate?.toIso8601String().substring(0, 10),
      'requested_race_place': draft.racePlace,
      'requested_race_url': draft.raceUrl,
    },
  ) as String;

  @override
  Future<void> delete(String postId) async {
    await _rpc('delete_board_post', {'post_id': postId});
  }
}
