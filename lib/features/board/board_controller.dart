import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runquest/shared/errors/server_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/board_service.dart';
import 'models/board_post.dart';

class BoardController extends ChangeNotifier {
  BoardController(this.service, {this.postId});

  final BoardService service;

  /// 알림에서 글 하나만 열 때의 글 ID입니다. 있으면 목록 대신 그 글만 불러옵니다.
  final String? postId;
  static const _timeout = Duration(seconds: 15);
  bool _disposed = false;
  int _generation = 0;
  BoardKind kind = BoardKind.local;
  BoardTopic? topic;

  /// 지금 게시판에서 찾는 검색어입니다. 없으면 전체 글을 보여줍니다.
  String? query;
  List<BoardPost> _posts = const [];
  BoardCursor? _next;
  String? region;
  bool canWrite = false;
  bool canPostRace = false;
  bool canModerate = false;
  bool loading = false;
  bool loadingMore = false;
  bool loaded = false;
  bool busy = false;
  String? error;

  List<BoardPost> get posts => _posts;
  bool get hasMore => _next != null;

  /// 동네를 정하지 않으면 동네 게시판은 비어 있으므로 설정을 먼저 안내합니다.
  bool get needsRegion => kind == BoardKind.local && loaded && region == null;
  bool get canCreate =>
      kind == BoardKind.race ? canPostRace : canWrite && !needsRegion;

  bool _checkOwner() {
    if (service.isCurrentOwner) return true;
    _posts = const [];
    _next = null;
    canWrite = canPostRace = canModerate = false;
    error = '다시 로그인해 주세요.';
    return false;
  }

  String _message(Object exception, String fallback) {
    if (exception is AuthException) return '다시 로그인해 주세요.';
    if (exception is TimeoutException) return '응답이 지연됩니다. 새로고침 후 다시 확인해 주세요.';
    if (exception is PostgrestException &&
        {'42501', '22023', 'P0001'}.contains(exception.code)) {
      return exception.message;
    }
    return unexpectedServerError(exception, fallback);
  }

  void select(BoardKind value) {
    if (_disposed || kind == value) return;
    kind = value;
    topic = null;
    query = null;
    unawaited(refresh());
  }

  /// 빈 검색어는 검색을 해제합니다.
  void search(String value) {
    final text = value.trim();
    final next = text.isEmpty ? null : text;
    if (_disposed || next == query) return;
    query = next;
    unawaited(refresh());
  }

  void selectTopic(BoardTopic? value) {
    if (_disposed || topic == value || kind == BoardKind.race) return;
    topic = value;
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    loadingMore = false;
    error = null;
    // 다른 게시판이나 말머리의 이전 글이 잠시라도 섞여 보이지 않게 지웁니다.
    _posts = const [];
    _next = null;
    notifyListeners();
    try {
      final id = postId;
      final feed =
          await (id == null
                  ? service.load(kind, topic: topic, query: query)
                  : service.loadPost(id))
              .timeout(_timeout);
      if (_disposed || generation != _generation) return;
      if (_checkOwner()) _apply(feed, append: false);
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      if (_checkOwner()) error = _message(exception, '글을 불러오지 못했습니다.');
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    final next = _next;
    if (_disposed || loading || loadingMore || next == null) return;
    final generation = _generation;
    loadingMore = true;
    error = null;
    notifyListeners();
    try {
      final feed = await service
          .load(kind, topic: topic, before: next, query: query)
          .timeout(_timeout);
      if (_disposed || generation != _generation) return;
      if (_checkOwner()) _apply(feed, append: true);
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      if (_checkOwner()) error = _message(exception, '다음 글을 불러오지 못했습니다.');
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void _apply(BoardFeed feed, {required bool append}) {
    final seen = {if (append) ..._posts.map((post) => post.id)};
    _posts = List.unmodifiable([
      if (append) ..._posts,
      ...feed.posts.where((post) => seen.add(post.id)),
    ]);
    _next = feed.next;
    region = feed.region;
    canWrite = feed.canWrite;
    canPostRace = feed.canPostRace;
    canModerate = feed.canModerate;
    loaded = true;
  }

  /// 성공하면 null, 실패하면 화면에 보여줄 안내 문구를 반환합니다.
  Future<String?> _mutate(
    Future<void> Function() action,
    String fallback,
  ) async {
    if (_disposed || busy) return '처리 중입니다. 잠시 후 다시 시도해 주세요.';
    if (!_checkOwner()) {
      notifyListeners();
      return error;
    }
    busy = true;
    notifyListeners();
    String? failure;
    try {
      await action().timeout(_timeout);
      if (!_disposed && !_checkOwner()) failure = error;
    } catch (exception) {
      if (!_disposed) {
        failure = _checkOwner() ? _message(exception, fallback) : error;
      }
    }
    if (_disposed) return failure;
    busy = false;
    // 성공 여부와 관계없이 서버 상태를 다시 조회합니다.
    await refresh();
    return failure;
  }

  Future<String?> changeRegion(String value) =>
      _mutate(() => service.setRegion(value), '동네를 저장하지 못했습니다.');

  Future<String?> create(BoardDraft draft) =>
      _mutate(() => service.create(draft), '글을 등록하지 못했습니다. 다시 시도해 주세요.');

  Future<String?> update(BoardPost post, BoardDraft draft) =>
      _mutate(() => service.update(post, draft), '글을 수정하지 못했습니다.');
  Future<String?> report(BoardPost post, String reason) =>
      _mutate(() => service.report(post.id, reason), '신고를 접수하지 못했습니다.');

  Future<String?> delete(BoardPost post) async {
    final error = await _mutate(
      () => service.delete(post.id),
      '글을 삭제하지 못했습니다.',
    );
    if (error == null && post.isMine) unawaited(removePhotos(post.images));
    return error;
  }

  BoardPost? postById(String id) {
    for (final post in _posts) {
      if (post.id == id) return post;
    }
    return null;
  }

  void _replace(String id, BoardPost Function(BoardPost post) change) {
    _posts = List.unmodifiable([
      for (final post in _posts) post.id == id ? change(post) : post,
    ]);
    notifyListeners();
  }

  /// 좋아요는 서버가 돌려준 상태와 개수로만 표시를 바꿉니다.
  Future<String?> setLike(BoardPost post, bool liked) async {
    if (_disposed || !_checkOwner()) return error;
    try {
      final result = await service.setLike(post.id, liked).timeout(_timeout);
      if (_disposed) return null;
      if (!_checkOwner()) {
        notifyListeners();
        return error;
      }
      _replace(
        post.id,
        (item) =>
            item.copyWith(liked: result.liked, likeCount: result.likeCount),
      );
      return null;
    } catch (exception) {
      if (_disposed) return null;
      return _checkOwner() ? _message(exception, '좋아요를 반영하지 못했습니다.') : error;
    }
  }

  void updateCommentCount(String postId, int count) {
    if (_disposed || postById(postId)?.commentCount == count) return;
    _replace(postId, (post) => post.copyWith(commentCount: count));
  }

  Future<String> uploadPhoto(Uint8List jpeg) async {
    if (!_checkOwner()) throw const AuthException('계정이 변경되었습니다.');
    return service.uploadPhoto(jpeg).timeout(const Duration(seconds: 30));
  }

  /// 저장하지 않았거나 글에서 뺀 사진을 지웁니다. 실패해도 글 작업은 막지 않습니다.
  Future<void> removePhotos(List<String> paths) async {
    if (paths.isEmpty || !service.isCurrentOwner) return;
    try {
      await service.removePhotos(paths).timeout(_timeout);
    } catch (_) {}
  }

  String photoError(Object exception) =>
      _message(exception, '사진을 올리지 못했습니다. 다시 시도해 주세요.');

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
