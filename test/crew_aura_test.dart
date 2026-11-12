import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/models/crew_aura.dart';

const _lat = 37.0, _lng = 127.0;
const _metersPerDegree = 111194.9;

void main() {
  late CrewAuraTracker tracker;
  var clock = DateTime.utc(2026, 11, 12, 9);

  // 호출할 때마다 10초씩 흘러 이동평균에 이전 위치가 섞이지 않게 합니다.
  DateTime tick([int seconds = 10]) =>
      clock = clock.add(Duration(seconds: seconds));

  AuraRunner me({int? pace}) => AuraRunner(
    id: CrewAuraState.selfId,
    latitude: _lat,
    longitude: _lng,
    at: clock,
    color: '#EF4444',
    paceSecPerKm: pace,
  );

  /// 나에게서 북쪽으로 [north]m, 동쪽으로 [east]m 떨어진 친구입니다.
  AuraRunner friend(String id, double north, {double east = 0, int? pace}) =>
      AuraRunner(
        id: id,
        latitude: _lat + north / _metersPerDegree,
        longitude: _lng + east / (_metersPerDegree * 0.7986),
        at: clock,
        color: '#3182F6',
        paceSecPerKm: pace,
      );

  CrewAuraState step(List<AuraRunner> Function() friends, {int? pace}) {
    tick();
    return tracker.update(
      self: me(pace: pace),
      friends: friends(),
    );
  }

  setUp(() => tracker = CrewAuraTracker());

  test('실제 거리를 미터로 계산합니다', () {
    expect(
      CrewAuraTracker.metersBetween(_lat, _lng, _lat + 0.001, _lng),
      closeTo(111.2, 0.2),
    );
    expect(CrewAuraTracker.metersBetween(_lat, _lng, _lat, _lng), 0);
  });

  test('600m 밖은 각자 오라, 600m 안은 빛줄기, 300m 안에서 합쳐집니다', () {
    var state = step(() => [friend('a', 700)]);
    expect(state.isSolo, isTrue);
    expect(state.links, isEmpty);
    expect(state.nearestMeters, closeTo(700, 1));

    state = step(() => [friend('a', 450)]);
    expect(state.nodes.single.id, 'a');
    expect(state.links.single.merged, isFalse);
    expect(state.links.single.meters, closeTo(450, 1));
    expect(state.nodes.single.crew, isNull);
    expect(state.joinedSelf, isFalse);

    // 300m 바로 바깥은 아직 합쳐지지 않은 굵은 빛줄기입니다.
    state = step(() => [friend('a', 320)]);
    expect(state.links.single.merged, isFalse);

    state = step(() => [friend('a', 250)]);
    expect(state.links.single.merged, isTrue);
    expect(state.joinedSelf, isTrue);
    expect(state.self.crew, 0);
    expect(state.nodes.single.crew, 0);
  });

  test('합쳐진 뒤에는 400m 밖으로 나가야 떨어집니다', () {
    step(() => [friend('a', 250)]);
    var state = step(() => [friend('a', 350)]);
    expect(state.links.single.merged, isTrue);
    // 이미 합쳐진 상태라 다시 합류로 알리지 않습니다.
    expect(state.joinedSelf, isFalse);

    state = step(() => [friend('a', 450)]);
    expect(state.links.single.merged, isFalse);
    expect(state.self.crew, isNull);

    // 떨어진 뒤 350m로 돌아와도 300m 안으로 들어오기 전에는 합쳐지지 않습니다.
    state = step(() => [friend('a', 350)]);
    expect(state.links.single.merged, isFalse);
    state = step(() => [friend('a', 290)]);
    expect(state.joinedSelf, isTrue);
  });

  test('친구 위치는 몇 초 동안의 평균으로 보정해 GPS가 튀어도 바로 떨어지지 않습니다', () {
    step(() => [friend('a', 250)]);
    tick(2);
    tracker.update(self: me(), friends: [friend('a', 250)]);
    // 한 번 640m로 튄 값은 앞의 두 값과 평균 내어 380m가 되어 떨어지지 않습니다.
    tick(2);
    final state = tracker.update(self: me(), friends: [friend('a', 640)]);
    expect(state.links.single.meters, closeTo(380, 1));
    expect(state.links.single.merged, isTrue);
    expect(
      (state.nodes.single.latitude - _lat) * _metersPerDegree,
      closeTo(380, 1),
    );
  });

  test('같은 시각의 위치를 여러 번 넣어도 평균이 달라지지 않습니다', () {
    tick();
    final friends = [friend('a', 350)];
    final first = tracker.update(self: me(), friends: friends);
    final again = tracker.update(self: me(), friends: friends);
    expect(again.links.single.meters, first.links.single.meters);
  });

  test('세 명이 모이면 한 무리가 되고, 나와 떨어진 친구끼리는 따로 무리를 이룹니다', () {
    var state = step(() => [friend('a', 200), friend('b', -200)]);
    expect(state.self.crew, 0);
    expect(state.nodes.map((node) => node.crew), [0, 0]);
    // a와 b는 서로 400m라 합쳐지지 않았지만 나를 통해 같은 무리입니다.
    expect(state.links.where((link) => link.merged), hasLength(2));

    tracker.reset();
    state = step(() => [friend('a', 450), friend('b', 450, east: 100)]);
    expect(state.self.crew, isNull);
    expect(state.nodes.map((node) => node.crew), [0, 0]);
    expect(state.joinedSelf, isFalse);
    expect(
      state.links.singleWhere((link) => link.merged),
      isA<AuraLink>()
          .having((link) => link.a, 'a', 'a')
          .having((link) => link.b, 'b', 'b'),
    );
  });

  test('페이스 차이가 10초 이내면 같은 박자, 크거나 모르면 어긋난 박자입니다', () {
    final state = step(
      () => [
        friend('a', 100, pace: 338),
        friend('b', -100, pace: 360),
        friend('c', 50, east: 100),
      ],
      pace: 330,
    );
    final sync = {for (final node in state.nodes) node.id: node.inSync};
    expect(sync, {'a': true, 'b': false, 'c': false});
    expect(state.self.inSync, isTrue);
  });

  test('가까운 순서로 여섯 명까지만 그리고 지도에 보낼 형식을 만듭니다', () {
    final state = step(
      () => [for (var i = 1; i <= 8; i++) friend('f$i', 50.0 * i)],
    );
    expect(state.nodes.map((node) => node.id), [
      'f1',
      'f2',
      'f3',
      'f4',
      'f5',
      'f6',
    ]);
    final json = state.toJson();
    expect(json['self'], {'color': '#EF4444', 'crew': 0, 'sync': true});
    final node = (json['nodes'] as List).first as Map;
    expect(node['id'], 'f1');
    expect(node['color'], '#3182F6');
    final link = (json['links'] as List).first as Map;
    expect(link['a'], 'self');
    expect(link['merged'], isTrue);
    expect(link['m'], 50);
    expect(json['limits'], {'merge': 300.0, 'split': 400.0, 'beam': 600.0});
  });

  test('오라를 끄면 합쳐진 기록을 지워 다시 켰을 때 처음부터 판정합니다', () {
    step(() => [friend('a', 250)]);
    tracker.reset();
    final state = step(() => [friend('a', 350)]);
    expect(state.links.single.merged, isFalse);
  });
}
