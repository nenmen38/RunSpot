import 'dart:async';

import 'package:runquest/features/progress/data/progress_service.dart';
import 'package:runquest/features/progress/models/run_progress.dart';

const testProgress = RunProgress(
  totalXp: 130,
  level: 2,
  levelXp: 30,
  nextLevelXp: 150,
);

class FakeProgressService implements ProgressService {
  FakeProgressService({
    this.progress = testProgress,
    this.rewards = const {},
    this.defaultReward,
  });
  @override
  bool isCurrentOwner = true;
  RunProgress progress;
  Map<String, RunReward?> rewards;
  RunReward? defaultReward;
  Object? loadFailure;
  Object? rewardFailure;
  Completer<void>? pendingReward;
  final rewardRequests = <String>[];
  int loads = 0;

  @override
  Future<RunProgress> load() async {
    loads++;
    if (loadFailure != null) throw loadFailure!;
    return progress;
  }

  @override
  Future<RunReward?> loadReward(String runId) async {
    rewardRequests.add(runId);
    await pendingReward?.future;
    if (rewardFailure != null) throw rewardFailure!;
    return rewards.containsKey(runId) ? rewards[runId] : defaultReward;
  }
}
