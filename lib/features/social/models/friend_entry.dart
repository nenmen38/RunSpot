enum FriendRelation { none, friend, sent, received }

enum FriendAction { request, accept, reject, cancel, remove }

class FriendEntry {
  const FriendEntry({
    required this.userId,
    required this.nickname,
    required this.relation,
    this.relationshipId,
    this.createdAt,
  });

  final String userId;
  final String nickname;
  final FriendRelation relation;
  final String? relationshipId;
  final DateTime? createdAt;

  factory FriendEntry.fromJson(Map<String, dynamic> json) => FriendEntry(
    userId: json['user_id'] as String,
    nickname: json['nickname'] as String,
    relation: FriendRelation.values.byName(json['relation'] as String),
    relationshipId: json['relationship_id'] as String?,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String),
  );
}

class FriendDashboard {
  FriendDashboard({
    required this.canInteract,
    required List<FriendEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final bool canInteract;
  final List<FriendEntry> entries;

  factory FriendDashboard.fromJson(Map<String, dynamic> json) =>
      FriendDashboard(
        canInteract: json['can_interact'] as bool,
        entries: (json['entries'] as List)
            .map(
              (row) =>
                  FriendEntry.fromJson(Map<String, dynamic>.from(row as Map)),
            )
            .toList(),
      );
}
