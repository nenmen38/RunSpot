import 'dart:async';

import 'package:runquest/features/board/data/board_service.dart';
import 'package:runquest/features/board/models/board_post.dart';

Map<String, dynamic> postJson(
  String id, {
  String board = 'local',
  String? topic = 'course',
  String? region = '서울특별시 강남구',
  bool isMine = false,
  String? raceDate,
}) => {
  'id': id,
  'board': board,
  'topic': topic,
  'region': region,
  'title': '제목$id',
  'body': '내용$id',
  'nickname': '러너$id',
  'is_mine': isMine,
  'race_date': raceDate,
  'race_place': raceDate == null ? null : '광화문',
  'race_url': raceDate == null ? null : 'https://example.com',
  'created_at': '2026-10-26T01:00:00.000000+00:00',
};

BoardFeed feed(
  List<Map<String, dynamic>> posts, {
  String? region = '서울특별시 강남구',
  bool canWrite = true,
  bool canPostRace = false,
  Map<String, dynamic>? next,
}) => BoardFeed.fromJson({
  'region': region,
  'can_write': canWrite,
  'can_post_race': canPostRace,
  'can_moderate': canPostRace,
  'posts': posts,
  'next': next,
});

class LoadCall {
  LoadCall(this.kind, this.topic, this.before);
  final BoardKind kind;
  final BoardTopic? topic;
  final BoardCursor? before;
}

class FakeBoardService implements BoardService {
  bool owner = true;
  final loads = <LoadCall>[];
  final created = <BoardDraft>[];
  final deleted = <String>[];
  final updated = <BoardDraft>[];
  final reported = <String>[];
  String? savedRegion;
  Future<BoardFeed> Function(LoadCall call)? onLoad;
  Object? createError;

  @override
  bool get isCurrentOwner => owner;

  @override
  Future<BoardFeed> load(
    BoardKind kind, {
    BoardTopic? topic,
    BoardCursor? before,
  }) {
    final call = LoadCall(kind, topic, before);
    loads.add(call);
    return onLoad?.call(call) ?? Future.value(feed(const []));
  }

  @override
  Future<String> setRegion(String region) async => savedRegion = region;

  @override
  Future<String> create(BoardDraft draft) async {
    if (createError != null) throw createError!;
    created.add(draft);
    return 'new-id';
  }

  @override
  Future<void> update(BoardPost post, BoardDraft draft) async =>
      updated.add(draft);
  @override
  Future<void> report(String postId, String reason) async =>
      reported.add('$postId:$reason');

  @override
  Future<void> delete(String postId) async => deleted.add(postId);
}
