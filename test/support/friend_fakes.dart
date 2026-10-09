import 'package:runquest/features/social/data/friend_service.dart';
import 'package:runquest/features/social/models/friend_entry.dart';

FriendEntry friendEntry(
  String id,
  FriendRelation relation, {
  String? nickname,
  String? relationshipId,
}) => FriendEntry(
  userId: id,
  nickname: nickname ?? '러너$id',
  relation: relation,
  relationshipId: relation == FriendRelation.none
      ? null
      : relationshipId ?? '관계$id',
);

class FakeFriendService implements FriendService {
  @override
  bool isCurrentOwner = true;
  bool canInteract = true;
  List<FriendEntry> entries = [];
  List<FriendEntry> directory = [friendEntry('1', FriendRelation.none)];
  int loads = 0;
  final searches = <String>[];
  final changes = <(FriendEntry, FriendAction)>[];
  Future<FriendDashboard> Function()? onLoad;
  Future<List<FriendEntry>> Function(String)? onSearch;
  Future<void> Function(FriendEntry, FriendAction)? onChange;

  @override
  Future<FriendDashboard> load() async {
    ++loads;
    return onLoad != null
        ? onLoad!()
        : FriendDashboard(canInteract: canInteract, entries: entries);
  }

  @override
  Future<List<FriendEntry>> search(String nickname) async {
    searches.add(nickname);
    if (onSearch != null) return onSearch!(nickname);
    return directory
        .where(
          (entry) => entry.nickname.toLowerCase() == nickname.toLowerCase(),
        )
        .map((entry) {
          return entries
                  .where((known) => known.userId == entry.userId)
                  .firstOrNull ??
              entry;
        })
        .toList();
  }

  @override
  Future<void> change(FriendEntry entry, FriendAction action) async {
    changes.add((entry, action));
    if (onChange != null) return onChange!(entry, action);
    entries = entries.where((known) => known.userId != entry.userId).toList();
    if (action == FriendAction.request || action == FriendAction.accept) {
      entries.add(
        friendEntry(
          entry.userId,
          action == FriendAction.request
              ? FriendRelation.sent
              : FriendRelation.friend,
          nickname: entry.nickname,
        ),
      );
    }
  }
}
