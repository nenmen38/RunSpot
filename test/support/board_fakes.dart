import 'dart:async';
import 'dart:typed_data';

import 'package:runquest/features/board/data/board_photo_service.dart';

import 'package:runquest/features/board/data/board_service.dart';
import 'package:runquest/features/board/models/board_post.dart';

Map<String, dynamic> postJson(
  String id, {
  String board = 'local',
  String? topic = 'course',
  String? region = '서울특별시 강남구',
  bool isMine = false,
  String? raceDate,
  List<String> images = const [],
  int likeCount = 0,
  bool liked = false,
  int commentCount = 0,
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
  'edited_at': null,
  'images': images,
  'like_count': likeCount,
  'liked': liked,
  'comment_count': commentCount,
};

Map<String, dynamic> commentJson(String id, {bool isMine = false}) => {
  'id': id,
  'body': '댓글$id',
  'nickname': '러너$id',
  'is_mine': isMine,
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

  final likes = <(String, bool)>[];
  int likeCount = 0;
  @override
  Future<({bool liked, int likeCount})> setLike(
    String postId,
    bool liked,
  ) async {
    likes.add((postId, liked));
    likeCount += liked ? 1 : -1;
    return (liked: liked, likeCount: likeCount);
  }

  List<Map<String, dynamic>> commentRows = [];
  bool canComment = true;
  Future<BoardComments> Function()? onComments;
  @override
  Future<BoardComments> comments(String postId) =>
      onComments?.call() ??
      Future.value(
        BoardComments.fromJson({
          'can_write': canComment,
          'can_moderate': false,
          'comments': commentRows,
        }),
      );

  final addedComments = <(String, String)>[];
  Object? commentError;
  @override
  Future<String> addComment(String clientId, String postId, String body) async {
    addedComments.add((clientId, body));
    if (commentError != null) throw commentError!;
    commentRows = [
      ...commentRows,
      commentJson('c${commentRows.length}', isMine: true),
    ];
    return 'c';
  }

  final deletedComments = <String>[];
  @override
  Future<void> deleteComment(String commentId) async {
    deletedComments.add(commentId);
    commentRows = commentRows.where((row) => row['id'] != commentId).toList();
  }

  final uploads = <Uint8List>[];
  @override
  Future<String> uploadPhoto(Uint8List jpeg) async {
    uploads.add(jpeg);
    return 'owner/${uploads.length}.jpg';
  }

  final removedPhotos = <String>[];
  @override
  Future<void> removePhotos(List<String> paths) async =>
      removedPhotos.addAll(paths);
}

class FakeBoardPhotoService implements BoardPhotoService {
  List<Uint8List> next = [];
  final limits = <int>[];

  @override
  Future<List<Uint8List>> pick(int limit) async {
    limits.add(limit);
    return next.take(limit).toList();
  }
}
