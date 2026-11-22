import 'dart:async';

import 'package:flutter/material.dart';

import '../monetization/cosmetics.dart';
import 'title_service.dart';

/// 화면에 나온 사람·글쓴이의 칭호와 꾸미기를 모아서 한 번에 불러오고 잠시 기억합니다.
/// 같은 사람을 여러 번 그려도 서버에는 한 번만 묻고, 5분이 지나면 다시 확인합니다.
class BadgeDirectory extends ChangeNotifier {
  BadgeDirectory._();
  static final instance = BadgeDirectory._();
  static const _maxAge = Duration(minutes: 5);

  TitleService? _service;
  final _users = <String, (UserBadge, DateTime)>{};
  final _posts = <String, (UserBadge, DateTime)>{};
  final _wantedUsers = <String>{};
  final _wantedPosts = <String>{};
  bool _scheduled = false;
  int _generation = 0;

  void bind(TitleService service) {
    _service = service;
    _clear();
  }

  void unbind() {
    _service = null;
    _clear();
  }

  void _clear() {
    _generation++;
    _users.clear();
    _posts.clear();
    _wantedUsers.clear();
    _wantedPosts.clear();
    notifyListeners();
  }

  /// 내 칭호나 꾸미기를 바꾼 뒤 화면에 보이는 칭호를 모두 다시 불러오게 합니다.
  void refreshAll() {
    _users.clear();
    _posts.clear();
    notifyListeners();
  }

  bool _fresh((UserBadge, DateTime)? entry) =>
      entry != null && DateTime.now().difference(entry.$2) < _maxAge;

  UserBadge? user(String id) {
    final entry = _users[id];
    if (!_fresh(entry)) _want(_wantedUsers, id);
    return entry?.$1;
  }

  UserBadge? post(String id) {
    final entry = _posts[id];
    if (!_fresh(entry)) _want(_wantedPosts, id);
    return entry?.$1;
  }

  void _want(Set<String> wanted, String id) {
    if (_service == null) return;
    wanted.add(id);
    if (_scheduled) return;
    _scheduled = true;
    // 한 화면을 그리는 동안 모인 요청을 묶어서 보냅니다.
    scheduleMicrotask(_flush);
  }

  Future<void> _flush() async {
    _scheduled = false;
    final service = _service;
    if (service == null || !service.isCurrentOwner) return;
    final generation = _generation;
    final users = _wantedUsers.take(100).toList();
    final posts = _wantedPosts.take(100).toList();
    _wantedUsers.removeAll(users);
    _wantedPosts.removeAll(posts);
    final now = DateTime.now();
    try {
      if (users.isNotEmpty) {
        final found = await service.userBadges(users);
        if (generation != _generation) return;
        for (final id in users) {
          _users[id] = (found[id] ?? const UserBadge(), now);
        }
      }
      if (posts.isNotEmpty) {
        final found = await service.postBadges(posts);
        if (generation != _generation) return;
        for (final id in posts) {
          _posts[id] = (found[id] ?? const UserBadge(), now);
        }
      }
      if (users.isNotEmpty || posts.isNotEmpty) notifyListeners();
    } catch (_) {
      // 칭호를 못 불러와도 화면은 그대로 씁니다. 실패한 것은 빈 칭호로 잠시 기억합니다.
      if (generation != _generation) return;
      for (final id in users) {
        _users[id] = (const UserBadge(), now);
      }
      for (final id in posts) {
        _posts[id] = (const UserBadge(), now);
      }
    }
    if (_wantedUsers.isNotEmpty || _wantedPosts.isNotEmpty) {
      _scheduled = true;
      scheduleMicrotask(_flush);
    }
  }
}

/// 사용자의 칭호 배지입니다. 칭호가 없으면 아무것도 그리지 않습니다.
class UserTitle extends StatelessWidget {
  const UserTitle({required this.userId, this.size = 11, super.key});

  final String userId;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: BadgeDirectory.instance,
    builder: (context, _) {
      final badge = BadgeDirectory.instance.user(userId);
      final title = badge?.title;
      if (title == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: TitleBadge(title: title, style: badge?.titleStyle, size: size),
      );
    },
  );
}

/// 목록에서 닉네임과 착용한 칭호를 한 줄로 보여줍니다.
class TitledNickname extends StatelessWidget {
  const TitledNickname(this.nickname, {this.userId, this.style, super.key});

  final String nickname;
  final String? userId;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Flexible(
        child: Text(
          nickname,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
      if (userId case final id?)
        Flexible(child: UserTitle(userId: id, size: 10)),
    ],
  );
}

/// 게시글 글쓴이의 칭호 배지입니다.
class PostAuthorTitle extends StatelessWidget {
  const PostAuthorTitle({required this.postId, this.size = 10, super.key});

  final String postId;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: BadgeDirectory.instance,
    builder: (context, _) {
      final badge = BadgeDirectory.instance.post(postId);
      final title = badge?.title;
      if (title == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: TitleBadge(title: title, style: badge?.titleStyle, size: size),
      );
    },
  );
}
