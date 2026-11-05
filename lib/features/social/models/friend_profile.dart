import '../../profile/models/achievement.dart';
import '../../profile/models/run_statistics.dart';
import '../../progress/models/run_progress.dart';

class FriendProfile {
  FriendProfile.fromJson(Map<String, dynamic> json)
    : nickname = json['nickname'] as String,
      progress = RunProgress.fromJson(
        Map<String, dynamic>.from(json['progress'] as Map),
      ),
      statistics = RunStatistics.fromJson(
        Map<String, dynamic>.from(json['statistics'] as Map),
      ),
      achievements = List.unmodifiable(
        (json['achievements'] as List).map(Achievement.fromJson),
      );

  final String nickname;
  final RunProgress progress;
  final RunStatistics statistics;
  final List<Achievement> achievements;
}
