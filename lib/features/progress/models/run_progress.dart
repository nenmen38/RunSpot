/// 서버가 계산한 누적 경험치와 현재 레벨 구간입니다.
class RunProgress {
  const RunProgress({
    required this.totalXp,
    required this.level,
    required this.levelXp,
    required this.nextLevelXp,
  });

  final int totalXp;
  final int level;

  /// 현재 레벨에 도달한 뒤 쌓은 경험치입니다.
  final int levelXp;

  /// 다음 레벨까지 필요한 구간 경험치입니다. 최대 레벨이면 null입니다.
  final int? nextLevelXp;

  bool get isMaxLevel => nextLevelXp == null;
  double get fraction =>
      isMaxLevel ? 1 : (levelXp / nextLevelXp!).clamp(0, 1).toDouble();
  int get remainingXp => isMaxLevel ? 0 : nextLevelXp! - levelXp;

  factory RunProgress.fromJson(Map<String, dynamic> json) {
    final total = json['total_xp'];
    final level = json['level'];
    final levelXp = json['level_xp'];
    final next = json['next_level_xp'];
    if (total is! int ||
        level is! int ||
        levelXp is! int ||
        (next != null && next is! int) ||
        total < 0 ||
        level < 1 ||
        level > 99 ||
        levelXp < 0 ||
        levelXp > total ||
        (next != null && (next <= 0 || levelXp >= next))) {
      throw const FormatException('경험치 응답이 올바르지 않습니다.');
    }
    return RunProgress(
      totalXp: total,
      level: level,
      levelXp: levelXp,
      nextLevelXp: next as int?,
    );
  }
}

enum RewardReason {
  tooShort,
  tooFast,
  lateSync,
  dailyLimit,
  rejected,
  reviewPending,
}

/// 러닝 보상은 일반 저장 또는 검토 승인 때 확정되며 조회로 재지급하지 않습니다.
class RunReward {
  const RunReward({
    required this.xp,
    required this.levelBefore,
    required this.levelAfter,
    required this.progress,
    this.reason,
  });

  final int xp;
  final RewardReason? reason;
  final int levelBefore;
  final int levelAfter;
  final RunProgress progress;

  bool get leveledUp => levelAfter > levelBefore;

  String? get reasonMessage => switch (reason) {
    RewardReason.tooShort => '300m 미만 기록은 경험치가 지급되지 않아요.',
    RewardReason.tooFast => '측정 속도가 비정상적으로 빨라 경험치가 지급되지 않았어요.',
    RewardReason.lateSync => '7일이 지나 저장된 기록은 경험치가 지급되지 않아요.',
    RewardReason.dailyLimit => '하루 최대 500 XP까지 받을 수 있어요.',
    RewardReason.reviewPending => '검토 중 · 승인 후 경험치 지급',
    RewardReason.rejected => '관리자 검토에서 반려되어 경험치가 제외되었어요.',
    null => null,
  };

  /// 보상 대상이 아닌 기록이면 null을 반환합니다.
  static RunReward? fromJson(Map<String, dynamic> json) {
    if (json['status'] == 'unavailable') return null;
    final xp = json['xp'];
    final before = json['level_before'];
    final after = json['level_after'];
    final progress = json['progress'];
    if (json['status'] != 'ready' ||
        xp is! int ||
        before is! int ||
        after is! int ||
        progress is! Map ||
        xp < 0 ||
        before < 1 ||
        after < before ||
        after > 99) {
      throw const FormatException('보상 응답이 올바르지 않습니다.');
    }
    final reason = switch (json['reason']) {
      null => null,
      'too_short' => RewardReason.tooShort,
      'too_fast' => RewardReason.tooFast,
      'late_sync' => RewardReason.lateSync,
      'daily_limit' => RewardReason.dailyLimit,
      'rejected' => RewardReason.rejected,
      'review_pending' => RewardReason.reviewPending,
      _ => throw const FormatException('보상 사유가 올바르지 않습니다.'),
    };
    return RunReward(
      xp: xp,
      reason: reason,
      levelBefore: before,
      levelAfter: after,
      progress: RunProgress.fromJson(Map<String, dynamic>.from(progress)),
    );
  }
}

String levelTitle(int level) => switch (level) {
  < 5 => '새내기 러너',
  < 10 => '꾸준한 러너',
  < 20 => '성장하는 러너',
  < 50 => '베테랑 러너',
  _ => '마스터 러너',
};
