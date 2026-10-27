enum BoardKind {
  local('local', '동네'),
  national('national', '전국'),
  race('race', '러닝 대회');

  const BoardKind(this.code, this.label);
  final String code;
  final String label;
}

enum BoardTopic {
  course('course', '추천 코스'),
  tip('tip', '꿀 정보'),
  food('food', '맛집');

  const BoardTopic(this.code, this.label);
  final String code;
  final String label;

  static BoardTopic? fromCode(String? code) {
    for (final topic in values) {
      if (topic.code == code) return topic;
    }
    return null;
  }
}

class BoardPost {
  const BoardPost({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.nickname,
    required this.isMine,
    required this.createdAt,
    required this.updatedAt,
    this.topic,
    this.region,
    this.raceDate,
    this.racePlace,
    this.raceUrl,
    this.images = const [],
    this.imageUrls = const {},
    this.likeCount = 0,
    this.liked = false,
    this.commentCount = 0,
  });

  BoardPost.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      kind = BoardKind.values.firstWhere((kind) => kind.code == json['board']),
      topic = BoardTopic.fromCode(json['topic'] as String?),
      region = json['region'] as String?,
      title = json['title'] as String,
      body = json['body'] as String,
      nickname = json['nickname'] as String,
      isMine = json['is_mine'] as bool,
      raceDate = json['race_date'] == null
          ? null
          : DateTime.parse(json['race_date'] as String),
      racePlace = json['race_place'] as String?,
      raceUrl = json['race_url'] as String?,
      createdAt = DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt = DateTime.parse(
        (json['updated_at'] ?? json['created_at']) as String,
      ).toUtc(),
      images = List.unmodifiable(
        (json['images'] as List? ?? const []).cast<String>(),
      ),
      imageUrls = const {},
      likeCount = json['like_count'] as int? ?? 0,
      liked = json['liked'] as bool? ?? false,
      commentCount = json['comment_count'] as int? ?? 0;

  final String id;
  final BoardKind kind;
  final BoardTopic? topic;
  final String? region;
  final String title;
  final String body;
  final String nickname;
  final bool isMine;
  final DateTime? raceDate;
  final String? racePlace;
  final String? raceUrl;
  final DateTime createdAt;

  /// 수정 충돌 확인에 쓰는 서버 기준 마지막 수정 시각입니다.
  final DateTime updatedAt;
  bool get isEdited => updatedAt.isAfter(createdAt);

  /// 저장소 안의 사진 경로입니다. 화면에는 [imageUrls]의 임시 주소로 표시합니다.
  final List<String> images;
  final Map<String, String> imageUrls;
  final int likeCount;
  final bool liked;
  final int commentCount;

  List<String> get visibleImageUrls => [
    for (final path in images)
      if (imageUrls[path] != null) imageUrls[path]!,
  ];

  BoardPost copyWith({
    Map<String, String>? imageUrls,
    int? likeCount,
    bool? liked,
    int? commentCount,
  }) => BoardPost(
    id: id,
    kind: kind,
    topic: topic,
    region: region,
    title: title,
    body: body,
    nickname: nickname,
    isMine: isMine,
    raceDate: raceDate,
    racePlace: racePlace,
    raceUrl: raceUrl,
    createdAt: createdAt,
    updatedAt: updatedAt,
    images: images,
    imageUrls: imageUrls ?? this.imageUrls,
    likeCount: likeCount ?? this.likeCount,
    liked: liked ?? this.liked,
    commentCount: commentCount ?? this.commentCount,
  );
}

class BoardComment {
  BoardComment.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      body = json['body'] as String,
      nickname = json['nickname'] as String,
      isMine = json['is_mine'] as bool,
      createdAt = DateTime.parse(json['created_at'] as String).toLocal();

  final String id;
  final String body;
  final String nickname;
  final bool isMine;
  final DateTime createdAt;
}

class BoardComments {
  BoardComments.fromJson(Map<String, dynamic> json)
    : canWrite = json['can_write'] as bool,
      canModerate = json['can_moderate'] as bool,
      comments = List.unmodifiable(
        (json['comments'] as List).map(
          (row) => BoardComment.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );

  final bool canWrite;
  final bool canModerate;
  final List<BoardComment> comments;
}

/// 서버가 반환한 마지막 글의 작성 시각·식별자로 다음 페이지를 조회합니다.
class BoardCursor {
  const BoardCursor(this.at, this.id);
  final String at;
  final String id;
}

class BoardFeed {
  const BoardFeed({
    required this.region,
    required this.canWrite,
    required this.canPostRace,
    required this.canModerate,
    required this.posts,
    this.next,
  });

  BoardFeed copyWith({List<BoardPost>? posts}) => BoardFeed(
    region: region,
    canWrite: canWrite,
    canPostRace: canPostRace,
    canModerate: canModerate,
    posts: posts ?? this.posts,
    next: next,
  );

  BoardFeed.fromJson(Map<String, dynamic> json)
    : region = json['region'] as String?,
      canWrite = json['can_write'] as bool,
      canPostRace = json['can_post_race'] as bool,
      canModerate = json['can_moderate'] as bool,
      posts = List.unmodifiable(
        (json['posts'] as List).map(
          (row) => BoardPost.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      ),
      next = json['next'] == null
          ? null
          : BoardCursor(
              (json['next'] as Map)['at'] as String,
              (json['next'] as Map)['id'] as String,
            );

  final String? region;
  final bool canWrite;
  final bool canPostRace;
  final bool canModerate;
  final List<BoardPost> posts;
  final BoardCursor? next;
}

class BoardDraft {
  const BoardDraft({
    required this.clientId,
    required this.kind,
    required this.title,
    required this.body,
    this.topic,
    this.raceDate,
    this.racePlace,
    this.raceUrl,
    this.images = const [],
  });

  /// 응답이 지연돼 다시 보내도 글이 한 번만 저장되도록 작성 화면마다 고정합니다.
  final String clientId;
  final BoardKind kind;
  final String title;
  final String body;
  final BoardTopic? topic;
  final DateTime? raceDate;
  final String? racePlace;
  final String? raceUrl;

  /// 이미 저장소에 올린 사진 경로입니다. 순서대로 표시합니다.
  final List<String> images;
}
