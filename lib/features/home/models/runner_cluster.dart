import 'package:latlong2/latlong.dart';

import '../../group_running/models/running_group.dart';
import 'live_runner.dart';

class RunnerCluster {
  RunnerCluster(this.members, {this.hostId});
  final List<LiveRunner> members;

  /// 함께 달리기를 신청한 사람(방장)입니다. 무리의 오라 색을 이 사람의 테두리 색으로 정합니다.
  final String? hostId;
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

/// 함께 달리는 참여자들이 이 거리(m) 안에 모두 모이면 한 덩어리로 묶습니다. 오라 합체 거리와 같습니다.
const groupMergeMeters = 300.0;

/// [solo]의 러너는 무리 표식으로 묶지 않고 각자 위치에 따로 보여줍니다.
/// 오라가 합쳐지는 러너는 아이콘을 각자 자리에 두어야 하기 때문입니다.
List<RunnerCluster> clusterRunners(
  List<LiveRunner> runners,
  List<RunningGroup> groups, {
  Set<String> solo = const {},
}) {
  const distance = Distance();
  final membership = <String, String>{};
  final hosts = <String, String>{};
  for (final group in groups) {
    if (group.state != 'running' || group.myStatus != 'accepted') continue;
    hosts[group.id] = group.hostId;
    for (final member in group.members) {
      if (member.status == 'accepted') membership[member.userId] = group.id;
    }
  }
  final clusters = <RunnerCluster>[];
  final ordered = [...runners]..sort((a, b) => a.id.compareTo(b.id));
  for (final runner in ordered) {
    final groupId = solo.contains(runner.id) ? null : membership[runner.id];
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
                        groupMergeMeters,
              ),
        )
        .firstOrNull;
    if (cluster == null) {
      clusters.add(
        RunnerCluster([
          runner,
        ], hostId: groupId == null ? null : hosts[groupId]),
      );
    } else {
      cluster.members.add(runner);
    }
  }
  return clusters;
}
