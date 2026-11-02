enum NotificationKind { like, comment, reply, groupInvite }

/// 내 게시글에 달린 좋아요·댓글, 내 댓글에 달린 답글과 함께 달리기 초대 알림입니다.
class AppNotification {
  AppNotification.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      kind = switch (json['kind']) {
        'comment' => NotificationKind.comment,
        'reply' => NotificationKind.reply,
        'group_invite' => NotificationKind.groupInvite,
        _ => NotificationKind.like,
      },
      postId = json['post_id'] as String?,
      postTitle = json['post_title'] as String?,
      groupId = json['group_id'] as String?,
      inviteStatus = json['invite_status'] as String?,
      canRespond = json['can_respond'] as bool? ?? false,
      nickname = json['nickname'] as String,
      comment = json['comment'] as String?,
      createdAt = DateTime.parse(json['created_at'] as String),
      read = json['read'] as bool? ?? false;

  final String id;
  final NotificationKind kind;

  /// 게시판 알림의 글입니다. 함께 달리기 초대에는 없습니다.
  final String? postId;
  final String? postTitle;

  /// 함께 달리기 초대의 그룹과 내 응답 상태입니다.
  final String? groupId;
  final String? inviteStatus;

  /// 아직 대기 중인 초대라 수락·거절할 수 있는지 여부입니다.
  final bool canRespond;
  final String nickname;
  final String? comment;

  /// 읽음 처리 기준으로 서버에 다시 보내므로 서버 시각 그대로 둡니다.
  final DateTime createdAt;
  final bool read;

  String get message => switch (kind) {
    NotificationKind.like => '$nickname님이 내 글을 좋아해요.',
    NotificationKind.comment => '$nickname님이 댓글을 남겼어요: $comment',
    NotificationKind.reply => '$nickname님이 내 댓글에 답글을 남겼어요: $comment',
    NotificationKind.groupInvite => '$nickname님이 함께 달리기에 초대했어요.',
  };

  /// 알림 아래 줄에 보여줄 글 제목이나 초대 응답 상태입니다.
  String get detail => kind == NotificationKind.groupInvite
      ? switch (inviteStatus) {
          _ when canRespond => '함께 달리기 초대',
          'accepted' || 'finished' => '참여했어요',
          'declined' => '거절했어요',
          _ => '끝난 초대예요',
        }
      : postTitle ?? '';
}
