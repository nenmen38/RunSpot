enum NotificationKind { like, comment }

/// 내 게시글에 달린 좋아요·댓글 알림입니다.
class AppNotification {
  AppNotification.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      kind = json['kind'] == 'comment'
          ? NotificationKind.comment
          : NotificationKind.like,
      postId = json['post_id'] as String,
      postTitle = json['post_title'] as String,
      nickname = json['nickname'] as String,
      comment = json['comment'] as String?,
      createdAt = DateTime.parse(json['created_at'] as String),
      read = json['read'] as bool? ?? false;

  final String id;
  final NotificationKind kind;
  final String postId;
  final String postTitle;
  final String nickname;
  final String? comment;

  /// 읽음 처리 기준으로 서버에 다시 보내므로 서버 시각 그대로 둡니다.
  final DateTime createdAt;
  final bool read;

  String get message => switch (kind) {
    NotificationKind.like => '$nickname님이 내 글을 좋아해요.',
    NotificationKind.comment => '$nickname님이 댓글을 남겼어요: $comment',
  };
}
