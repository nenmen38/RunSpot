class ReviewCase {
  const ReviewCase({
    required this.user,
    required this.reason,
    required this.summary,
    required this.risk,
    required this.status,
  });

  final String user;
  final String reason;
  final String summary;
  final int risk;
  final String status;

  ReviewCase copyWith({String? status}) {
    return ReviewCase(
      user: user,
      reason: reason,
      summary: summary,
      risk: risk,
      status: status ?? this.status,
    );
  }
}
