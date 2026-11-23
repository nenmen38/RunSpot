import '../../titles/title_service.dart';

class RunnerRank {
  const RunnerRank(
    this.rank,
    this.name,
    this.badge,
    this.value,
    this.isMe, {
    this.titleBadge,
  });

  final int rank;
  final String name;
  final String badge;
  final String value;
  final bool isMe;
  final UserBadge? titleBadge;
}
