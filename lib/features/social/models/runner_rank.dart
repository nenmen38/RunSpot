class RunnerRank {
  const RunnerRank(
    this.rank,
    this.name,
    this.badge,
    this.value,
    this.isMe, {
    this.userId,
  });

  final int rank;
  final String name;
  final String badge;
  final String value;
  final bool isMe;
  final String? userId;
}
