import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runquest/shared/errors/server_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'data/board_service.dart';
import 'models/board_post.dart';

class BoardCommentsController extends ChangeNotifier {
  BoardCommentsController(this.service, this.postId, {this.onCount});

  final BoardService service;
  final String postId;

  /// 목록의 댓글 수를 서버가 돌려준 개수로 맞춥니다.
  final ValueChanged<int>? onCount;
  static const _timeout = Duration(seconds: 15);
  bool _disposed = false;
  int _generation = 0;
  List<BoardComment> _comments = const [];
  bool canWrite = false;
  bool canModerate = false;
  bool loading = false;
  bool loaded = false;
  bool busy = false;
  String? error;

  // 같은 내용을 다시 보내면 서버가 같은 댓글로 처리하도록 식별자를 유지합니다.
  String? _pendingKey;
  String _pendingId = const Uuid().v4();

  List<BoardComment> get comments => _comments;

  String _message(Object exception, String fallback) {
    if (exception is AuthException) return '다시 로그인해 주세요.';
    if (exception is TimeoutException) return '응답이 지연됩니다. 다시 확인해 주세요.';
    if (exception is PostgrestException &&
        {'42501', '22023', 'P0001'}.contains(exception.code)) {
      return exception.message;
    }
    return unexpectedServerError(exception, fallback);
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await service.comments(postId).timeout(_timeout);
      if (_disposed || generation != _generation) return;
      if (!service.isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
      _comments = result.comments;
      canWrite = result.canWrite;
      canModerate = result.canModerate;
      loaded = true;
      onCount?.call(_comments.length);
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      _comments = const [];
      error = _message(exception, '댓글을 불러오지 못했습니다.');
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<String?> _mutate(
    Future<void> Function() action,
    String fallback,
  ) async {
    if (_disposed || busy) return null;
    busy = true;
    notifyListeners();
    String? failure;
    try {
      await action().timeout(_timeout);
    } catch (exception) {
      failure = _message(exception, fallback);
    }
    if (_disposed) return failure;
    busy = false;
    await refresh();
    return failure;
  }

  /// 성공하면 null, 실패하면 안내 문구를 반환합니다.
  /// [parent]가 있으면 그 댓글의 답글로 등록하고, 답글에 답하면 원댓글 아래에 답니다.
  Future<String?> add(String body, {BoardComment? parent}) async {
    final text = body.trim();
    if (text.isEmpty) return '댓글을 입력해 주세요.';
    if (text.length > 500) return '댓글은 500자 이내로 입력해 주세요.';
    final parentId = parent?.parentId ?? parent?.id;
    final key = '$parentId\n$text';
    if (_pendingKey != key) {
      _pendingKey = key;
      _pendingId = const Uuid().v4();
    }
    final id = _pendingId;
    final error = await _mutate(
      () => service.addComment(id, postId, text, parentId: parentId),
      '댓글을 등록하지 못했습니다. 다시 시도해 주세요.',
    );
    if (error == null) _pendingKey = null;
    return error;
  }

  /// 원댓글 아래에 답글을 묶은 표시 순서입니다. 원댓글이 없는 답글은 보여주지 않습니다.
  List<({BoardComment comment, bool isReply})> get threads {
    final replies = <String, List<BoardComment>>{};
    for (final comment in _comments) {
      final parent = comment.parentId;
      if (parent != null) (replies[parent] ??= []).add(comment);
    }
    return [
      for (final comment in _comments)
        if (comment.parentId == null) ...[
          (comment: comment, isReply: false),
          for (final reply in replies[comment.id] ?? const <BoardComment>[])
            (comment: reply, isReply: true),
        ],
    ];
  }

  /// 좋아요는 서버가 돌려준 상태와 개수로만 표시를 바꿉니다.
  Future<String?> setLike(BoardComment comment) async {
    if (_disposed) return null;
    try {
      final result = await service
          .setCommentLike(comment.id, !comment.liked)
          .timeout(_timeout);
      if (_disposed) return null;
      if (!service.isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
      _comments = List.unmodifiable([
        for (final item in _comments)
          item.id == comment.id
              ? item.copyWith(liked: result.liked, likeCount: result.likeCount)
              : item,
      ]);
      notifyListeners();
      return null;
    } catch (exception) {
      if (_disposed) return null;
      return _message(exception, '좋아요를 반영하지 못했습니다.');
    }
  }

  Future<String?> delete(BoardComment comment) =>
      _mutate(() => service.deleteComment(comment.id), '댓글을 삭제하지 못했습니다.');

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
