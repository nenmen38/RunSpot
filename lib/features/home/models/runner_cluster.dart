import 'package:latlong2/latlong.dart';

import '../../group_running/models/running_group.dart';
import 'live_runner.dart';

class RunnerCluster {
  RunnerCluster(this.members);
  final List<LiveRunner> members;
  String get id => members.length == 1
      ? members.single.id
      : 'group:${members.map((member) => member.id).join(':')}';
  LatLng get point => LatLng(
    members.fold<double>(0, (sum, member) => sum + member.latitude) /
        members.length,
    members.fold<double>(0, (sum, member) => sum + member.longitude) /
        members.length,
  );
}

List<RunnerCluster> clusterRunners(
  List<LiveRunner> runners,
  List<RunningGroup> groups,
) {
  const distance = Distance();
  final membership = <String, String>{};
  for (final group in groups) {
    if (group.state != 'running' || group.myStatus != 'accepted') continue;
    for (final member in group.members) {
      if (member.status == 'accepted') membership[member.userId] = group.id;
    }
  }
  final clusters = <RunnerCluster>[];
  final ordered = [...runners]..sort((a, b) => a.id.compareTo(b.id));
  for (final runner in ordered) {
    final groupId = membership[runner.id];
    // 모든 구성원과 가까울 때만 합쳐 긴 대열이 하나로 묶이지 않게 합니다.
    final cluster = clusters
        .where(
          (cluster) =>
              groupId != null &&
              cluster.members.every(
                (member) =>
                    membership[member.id] == groupId &&
                    distance.as(
                          LengthUnit.Meter,
                          LatLng(member.latitude, member.longitude),
                          LatLng(runner.latitude, runner.longitude),
                        ) <=
                        30,
              ),
        )
        .firstOrNull;
    if (cluster == null) {
      clusters.add(RunnerCluster([runner]));
    } else {
      cluster.members.add(runner);
    }
  }
  return clusters;
}
