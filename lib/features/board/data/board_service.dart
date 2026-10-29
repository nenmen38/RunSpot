import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/board_post.dart';

abstract interface class BoardService {
  bool get isCurrentOwner;

  /// [query]가 있으면 제목·내용에 검색어가 들어간 글만 불러옵니다.
  Future<BoardFeed> load(
    BoardKind kind, {
    BoardTopic? topic,
    BoardCursor? before,
    String? query,
  });

  /// 알림에서 여는 글 하나를 목록과 같은 형식으로 불러옵니다.
  Future<BoardFeed> loadPost(String postId);
  Future<String> setRegion(String region);
  Future<String> create(BoardDraft draft);
  Future<void> update(BoardPost post, BoardDraft draft);
  Future<void> report(String postId, String reason);
  Future<void> delete(String postId);
  Future<({bool liked, int likeCount})> setLike(String postId, bool liked);
  Future<BoardComments> comments(String postId);

  /// [parentId]가 있으면 그 댓글의 답글로 등록합니다.
  Future<String> addComment(
    String clientId,
    String postId,
    String body, {
    String? parentId,
  });
  Future<void> deleteComment(String commentId);

  /// 메타데이터를 제거한 JPEG를 본인 폴더에 올리고 저장소 경로를 반환합니다.
  Future<String> uploadPhoto(Uint8List jpeg);
  Future<void> removePhotos(List<String> paths);
}

class SupabaseBoardService implements BoardService {
  SupabaseBoardService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;
  static const bucket = 'board-images';

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  void _requireOwner() {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) async {
    _requireOwner();
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    _requireOwner();
    return result;
  }

  @override
  Future<BoardFeed> load(
    BoardKind kind, {
    BoardTopic? topic,
    BoardCursor? before,
    String? query,
  }) async {
    return _withImageUrls(
      BoardFeed.fromJson(
        Map<String, dynamic>.from(
          await _rpc('board_feed', {
            'requested_board': kind.code,
            'requested_topic': topic?.code,
            'before_at': before?.at,
            'before_id': before?.id,
            'search_text': ?query,
          }) as Map,
        ),
      ),
    );
  }

  @override
  Future<BoardFeed> loadPost(String postId) async => _withImageUrls(
    BoardFeed.fromJson(
      Map<String, dynamic>.from(
        await _rpc('board_post', {'post_id': postId}) as Map,
      ),
    ),
  );

  Future<BoardFeed> _withImageUrls(BoardFeed feed) async {
    final paths = {for (final post in feed.posts) ...post.images}.toList();
    if (paths.isEmpty) return feed;
    // 비공개 사진은 한 번에 1시간짜리 임시 주소로 바꿉니다. 실패한 사진만 빈칸으로 둡니다.
    final signed = await client.storage
        .from(bucket)
        .createSignedUrlsResult(paths, 3600);
    _requireOwner();
    final urls = {
      for (final item in signed)
        if (item case SignedUrlSuccess(:final path, :final signedUrl))
          path: signedUrl,
    };
    return feed.copyWith(
      posts: [
        for (final post in feed.posts)
          post.copyWith(
            imageUrls: {
              for (final path in post.images)
                if (urls[path] != null) path: urls[path]!,
            },
          ),
      ],
    );
  }

  @override
  Future<String> setRegion(String region) async =>
      await _rpc('set_my_board_region', {'requested_region': region}) as String;

  Map<String, dynamic> _fields(BoardDraft draft) => {
    'requested_title': draft.title,
    'requested_body': draft.body,
    'requested_topic': draft.topic?.code,
    'requested_race_date': draft.raceDate?.toIso8601String().substring(0, 10),
    'requested_race_place': draft.racePlace,
    'requested_race_url': draft.raceUrl,
    'requested_images': draft.images,
  };

  @override
  Future<String> create(BoardDraft draft) async =>
      await _rpc('create_board_post', {
        'client_id': draft.clientId,
        'requested_board': draft.kind.code,
        ..._fields(draft),
      }) as String;

  @override
  Future<void> update(BoardPost post, BoardDraft draft) async {
    await _rpc('update_my_board_post', {
      'post_id': post.id,
      'expected_updated_at': post.updatedAt.toIso8601String(),
      ..._fields(draft),
    });
  }

  @override
  Future<void> report(String postId, String reason) async {
    await _rpc('report_board_post', {
      'post_id': postId,
      'requested_reason': reason,
    });
  }

  @override
  Future<void> delete(String postId) async {
    await _rpc('delete_board_post', {'post_id': postId});
  }

  @override
  Future<({bool liked, int likeCount})> setLike(
    String postId,
    bool liked,
  ) async {
    final result = Map<String, dynamic>.from(
      await _rpc('set_board_like', {'post_id': postId, 'liked': liked}) as Map,
    );
    return (
      liked: result['liked'] as bool,
      likeCount: result['like_count'] as int,
    );
  }

  @override
  Future<BoardComments> comments(String postId) async => BoardComments.fromJson(
    Map<String, dynamic>.from(
      await _rpc('board_comments', {'post_id': postId}) as Map,
    ),
  );

  @override
  Future<String> addComment(
    String clientId,
    String postId,
    String body, {
    String? parentId,
  }) async => await _rpc('create_board_comment', {
    'client_id': clientId,
    'post_id': postId,
    'requested_body': body,
    'parent_comment_id': ?parentId,
  }) as String;

  @override
  Future<void> deleteComment(String commentId) async {
    await _rpc('delete_board_comment', {'comment_id': commentId});
  }

  @override
  Future<String> uploadPhoto(Uint8List jpeg) async {
    _requireOwner();
    final path = '$_owner/${const Uuid().v4()}.jpg';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    _requireOwner();
    return path;
  }

  @override
  Future<void> removePhotos(List<String> paths) async {
    if (paths.isEmpty) return;
    _requireOwner();
    // 본인 폴더의 사진만 지울 수 있으며 저장소 정책이 다시 확인합니다.
    await client.storage
        .from(bucket)
        .remove(paths.where((path) => path.startsWith('$_owner/')).toList());
  }
}
