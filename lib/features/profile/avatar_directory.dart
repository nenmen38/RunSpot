import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/data/account_rpc.dart';
import 'data/profile_avatar_service.dart';

/// 사람(사용자 ID)·글쓴이(글 ID)·댓글 작성자(댓글 ID)의 작은 프로필 사진을 서버에 묻습니다.
/// 결과는 종류별로 {ID: 사진 바이트}이며 사진이 없거나 볼 수 없는 사람은 빠집니다.
abstract interface class AvatarSource {
  bool get isCurrentOwner;
  Future<
    ({
      Map<String, Uint8List> users,
      Map<String, Uint8List> posts,
      Map<String, Uint8List> comments,
    })
  >
  load({
    List<String> users = const [],
    List<String> posts = const [],
    List<String> comments = const [],
  });
}

class SupabaseAvatarSource implements AvatarSource {
  SupabaseAvatarSource(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentUser?.id == _owner;

  @override
  Future<
    ({
      Map<String, Uint8List> users,
      Map<String, Uint8List> posts,
      Map<String, Uint8List> comments,
    })
  >
  load({
    List<String> users = const [],
    List<String> posts = const [],
    List<String> comments = const [],
  }) async {
    final result = Map<String, dynamic>.from(
      await client.rpc(
        'profile_avatars',
        params: {'user_ids': users, 'post_ids': posts, 'comment_ids': comments},
      ) as Map,
    );
    Map<String, Uint8List> photos(String key) => {
      for (final entry in Map<String, dynamic>.from(
        result[key] as Map? ?? const {},
      ).entries)
        if ((entry.value as Map?)?['photo'] case final String photo)
          entry.key: decodeAvatarBase64(photo),
    };
    return (
      users: photos('users'),
      posts: photos('posts'),
      comments: photos('comments'),
    );
  }
}

enum _Kind { user, post, comment }

/// 화면에 나온 사람들의 프로필 사진을 모아서 한 번에 불러오고 잠시 기억합니다.
/// 같은 사람을 여러 번 그려도 서버에는 한 번만 묻고, 5분이 지나면 다시 확인합니다.
class AvatarDirectory extends ChangeNotifier {
  AvatarDirectory._();
  static final instance = AvatarDirectory._();
  static const _maxAge = Duration(minutes: 5);

  AvatarSource? _source;
  final _cache = <_Kind, Map<String, (ImageProvider?, DateTime)>>{
    for (final kind in _Kind.values) kind: {},
  };
  final _wanted = <_Kind, Set<String>>{
    for (final kind in _Kind.values) kind: {},
  };
  bool _scheduled = false;
  int _generation = 0;

  AccountRpc? _reports;
  AccountRpc? get reports => _reports;

  void bind(AvatarSource source, {AccountRpc? reports}) {
    _reports = reports;
    _source = source;
    _clear();
  }

  void unbind() {
    _reports = null;
    _source = null;
    _clear();
  }

  void _clear() {
    _generation++;
    for (final kind in _Kind.values) {
      _cache[kind]!.clear();
      _wanted[kind]!.clear();
    }
    notifyListeners();
  }

  /// 내 사진을 바꾼 뒤 모든 화면의 사진을 다시 불러오게 합니다. 내 사진은 바로 바꿔 보여줍니다.
  void updateMine(String userId, Uint8List? photo) {
    for (final kind in _Kind.values) {
      _cache[kind]!.clear();
    }
    _cache[_Kind.user]![userId] = (
      photo == null ? null : MemoryImage(photo),
      DateTime.now(),
    );
    notifyListeners();
  }

  ImageProvider? user(String id) => _get(_Kind.user, id);
  ImageProvider? post(String id) => _get(_Kind.post, id);
  ImageProvider? comment(String id) => _get(_Kind.comment, id);

  ImageProvider? _get(_Kind kind, String id) {
    final entry = _cache[kind]![id];
    if (entry == null || DateTime.now().difference(entry.$2) >= _maxAge) {
      _want(kind, id);
    }
    return entry?.$1;
  }

  void _want(_Kind kind, String id) {
    if (_source == null || id.isEmpty) return;
    _wanted[kind]!.add(id);
    if (_scheduled) return;
    _scheduled = true;
    // 한 화면을 그리는 동안 모인 요청을 묶어서 보냅니다.
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _scheduled = false;
    final source = _source;
    if (source == null || !source.isCurrentOwner) return;
    final generation = _generation;
    final batch = {
      for (final kind in _Kind.values) kind: _wanted[kind]!.take(100).toList(),
    };
    for (final kind in _Kind.values) {
      _wanted[kind]!.removeAll(batch[kind]!);
    }
    if (batch.values.every((ids) => ids.isEmpty)) return;
    final now = DateTime.now();
    try {
      final found = await source.load(
        users: batch[_Kind.user]!,
        posts: batch[_Kind.post]!,
        comments: batch[_Kind.comment]!,
      );
      if (generation != _generation) return;
      final byKind = {
        _Kind.user: found.users,
        _Kind.post: found.posts,
        _Kind.comment: found.comments,
      };
      for (final kind in _Kind.values) {
        for (final id in batch[kind]!) {
          final photo = byKind[kind]![id];
          _cache[kind]![id] = (photo == null ? null : MemoryImage(photo), now);
        }
      }
      notifyListeners();
    } catch (_) {
      // 사진을 못 불러와도 화면은 첫 글자로 보여줍니다. 실패한 것은 잠시 '사진 없음'으로 기억합니다.
      if (generation != _generation) return;
      for (final kind in _Kind.values) {
        for (final id in batch[kind]!) {
          _cache[kind]![id] = (null, now);
        }
      }
    }
    if (_wanted.values.any((ids) => ids.isNotEmpty)) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
  }
}

/// 프로필 사진 동그라미입니다. 사진이 없으면 닉네임 첫 글자를 보여줍니다.
/// [userId]·[postId](글쓴이)·[commentId](댓글 작성자) 중 하나로 사진을 찾습니다.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.nickname,
    this.userId,
    this.postId,
    this.commentId,
    this.size = 38,
    super.key,
  });

  final String nickname;
  final String? userId;
  final String? postId;
  final String? commentId;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AvatarDirectory.instance,
    builder: (context, _) {
      final directory = AvatarDirectory.instance;
      final photo = switch ((userId, postId, commentId)) {
        (final String id, _, _) => directory.user(id),
        (_, final String id, _) => directory.post(id),
        (_, _, final String id) => directory.comment(id),
        _ => null,
      };
      final initials = nickname.trim().characters;
      return ExcludeSemantics(
        child: CircleAvatar(
          radius: size / 2,
          backgroundColor: AppColors.blueSoft,
          foregroundColor: AppColors.blueText,
          foregroundImage: photo,
          child: photo != null
              ? null
              : Text(
                  initials.isEmpty ? '?' : initials.first,
                  style: TextStyle(
                    fontSize: size * .4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      );
    },
  );
}
