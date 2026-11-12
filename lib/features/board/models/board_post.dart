import '../../crew/models/crew.dart';

enum BoardKind {
  local('local', '우리 동네'),
  national('national', '러닝 소식'),
  race('race', '러닝 대회'),

  /// 크루장만 쓰는 크루 소개·크루원 모집 글입니다. 말머리 없이 크루 이름을 붙입니다.
  crew('crew', '크루 홍보'),

  /// 목록 전용입니다. 전국 글과 내 동네 글을 함께 보여주며 글은 [national]·[local]로 저장합니다.
  news('news', '러닝 소식');

  const BoardKind(this.code, this.label);
  final String code;
  final String label;
}

enum BoardTopic {
  course('course', '러닝 코스'),
  tip('tip', '러닝 팁'),
  food('food', '맛집·카페'),
  free('free', '자유'),
  question('question', '질문');

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

/// 크루 홍보글에 붙는 크루 이름과 아이콘입니다.
class BoardCrew {
  const BoardCrew({required this.id, required this.name, required this.icon});

  BoardCrew.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      icon = CrewIcon.fromCode(json['icon']);

  final String id;
  final String name;
  final CrewIcon icon;
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
    this.crew,
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
      commentCount = json['comment_count'] as int? ?? 0,
      crew = json['crew'] == null
          ? null
          : BoardCrew.fromJson(Map<String, dynamic>.from(json['crew'] as Map));

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

  /// 크루 홍보글이면 그 크루입니다.
  final BoardCrew? crew;

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
    crew: crew,
  );
}

class BoardComment {
  const BoardComment({
    required this.id,
    required this.body,
    required this.nickname,
    required this.isMine,
    required this.createdAt,
    this.parentId,
    this.likeCount = 0,
    this.liked = false,
  });

  BoardComment.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      body = json['body'] as String,
      nickname = json['nickname'] as String,
      isMine = json['is_mine'] as bool,
      parentId = json['parent_id'] as String?,
      createdAt = DateTime.parse(json['created_at'] as String).toLocal(),
      likeCount = json['like_count'] as int? ?? 0,
      liked = json['liked'] as bool? ?? false;

  final String id;

  /// 답글이면 원댓글 ID입니다. 답글은 한 단계만 있습니다.
  final String? parentId;
  final String body;
  final String nickname;
  final bool isMine;
  final DateTime createdAt;
  final int likeCount;
  final bool liked;

  BoardComment copyWith({int? likeCount, bool? liked}) => BoardComment(
    id: id,
    body: body,
    nickname: nickname,
    isMine: isMine,
    createdAt: createdAt,
    parentId: parentId,
    likeCount: likeCount ?? this.likeCount,
    liked: liked ?? this.liked,
  );
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
    this.ownCrews = const [],
  });

  BoardFeed copyWith({List<BoardPost>? posts}) => BoardFeed(
    region: region,
    canWrite: canWrite,
    canPostRace: canPostRace,
    canModerate: canModerate,
    posts: posts ?? this.posts,
    next: next,
    ownCrews: ownCrews,
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
      ownCrews = List.unmodifiable(
        (json['own_crews'] as List? ?? const []).map(
          (row) => BoardCrew.fromJson(Map<String, dynamic>.from(row as Map)),
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

  /// 내가 크루장인 크루입니다. 있으면 크루 홍보글을 쓸 수 있습니다.
  final List<BoardCrew> ownCrews;
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
    this.crewId,
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

  /// 크루 홍보글을 올릴 크루입니다.
  final String? crewId;
}
