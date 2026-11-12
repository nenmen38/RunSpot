import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/group_running/models/running_group.dart';
import 'package:runquest/features/home/models/live_runner.dart';
import 'package:runquest/features/home/models/runner_cluster.dart';

LiveRunner runner(String id, double offset) => LiveRunner(
  id: id,
  nickname: id,
  latitude: 37 + offset,
  longitude: 127,
  distanceMeters: 100,
  updatedAt: DateTime.now(),
);
RunningGroup group(
  List<String> ids, {
  String state = 'running',
  String status = 'accepted',
}) => RunningGroup.fromJson({
  'id': 'group',
  'host_id': ids.first,
  'state': state,
  'my_status': status,
  'members': [
    for (final id in ids) {'user_id': id, 'nickname': id, 'status': 'accepted'},
  ],
});
void main() {
  test('같은 그룹의 가까운 참여자만 합치며 멀어지면 분리합니다', () {
    final groups = [
      group(['a', 'b']),
    ];
    expect(
      clusterRunners([
        runner('a', 0),
        runner('b', .0001),
        runner('other', 0),
      ], groups).map((cluster) => cluster.members.length),
      [2, 1],
    );
    expect(
      // 300m 밖(약 440m)은 따로 보여줍니다.
      clusterRunners([runner('a', 0), runner('b', .004)], groups).length,
      2,
    );
  });
  test('대기 그룹과 초대만 받은 그룹은 합치지 않습니다', () {
    final runners = [runner('a', 0), runner('b', 0)];
    expect(
      clusterRunners(runners, [
        group(['a', 'b'], state: 'lobby'),
      ]).length,
      2,
    );
    expect(
      clusterRunners(runners, [
        group(['a', 'b'], status: 'invited'),
      ]).length,
      2,
    );
  });
  test('긴 대열은 모두 합치지 않고 입력 순서와 무관하게 묶습니다', () {
    // a-b, b-c는 약 220m, a-c는 약 440m입니다.
    final runners = [runner('a', 0), runner('b', .002), runner('c', .004)];
    final groups = [
      group(['a', 'b', 'c']),
    ];
    final clusters = clusterRunners(runners, groups);
    expect(clusters.map((cluster) => cluster.members.length), [2, 1]);
    expect(
      clusterRunners(
        runners.reversed.toList(),
        groups,
      ).map((cluster) => cluster.id),
      clusters.map((cluster) => cluster.id),
    );
  });
  test('조회에서 사라진 참여자는 인원수와 중심 위치에서 제외합니다', () {
    final clusters = clusterRunners(
      [runner('a', 0)],
      [
        group(['a', 'b']),
      ],
    );
    expect(clusters.single.members.length, 1);
    expect(clusters.single.point.latitude, 37);
  });

  test('300m 안에 모이면 한 덩어리가 되고 방장을 함께 기억합니다', () {
    final clusters = clusterRunners(
      [runner('b', 0), runner('a', .0025), runner('c', .0012)],
      [
        group(['a', 'b', 'c']),
      ],
    );
    expect(clusters.single.members.length, 3);
    expect(clusters.single.hostId, 'a');
    expect(groupMergeMeters, 300);
    // 그룹이 아닌 러너에는 방장이 없습니다.
    expect(clusterRunners([runner('x', 0)], const []).single.hostId, isNull);
  });
}
