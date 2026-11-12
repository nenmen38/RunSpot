import 'dart:math' as math;

/// 오라를 착용한 러너 한 명의 최신 위치입니다. 내 위치도 같은 형태로 넣습니다.
class AuraRunner {
  const AuraRunner({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.at,
    required this.color,
    this.paceSecPerKm,
  });

  final String id;
  final double latitude;
  final double longitude;

  /// 이 위치를 잰 시각입니다. 같은 시각의 위치는 한 번만 반영합니다.
  final DateTime at;

  /// 오라 색(#RRGGBB)입니다.
  final String color;
  final int? paceSecPerKm;
}

/// 화면에 그릴 오라 한 개입니다. 위치는 이동평균으로 보정한 값입니다.
class AuraNode {
  const AuraNode({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.color,
    required this.crew,
    required this.inSync,
  });

  final String id;
  final double latitude;
  final double longitude;
  final String color;

  /// 합쳐진 무리의 번호입니다. 같은 번호끼리 하나의 오라로 그립니다. 혼자면 null입니다.
  final int? crew;

  /// 무리의 기준 러너와 페이스가 비슷해 같은 박자로 맥동하는지 여부입니다.
  final bool inSync;
}

/// 두 러너 사이의 연결입니다. [merged]가 아니면 빛줄기로 그립니다.
class AuraLink {
  const AuraLink(this.a, this.b, this.meters, {required this.merged});

  final String a;
  final String b;
  final double meters;
  final bool merged;
}

class CrewAuraState {
  const CrewAuraState({
    required this.self,
    required this.nodes,
    required this.links,
    required this.joinedSelf,
    required this.nearestMeters,
  });

  static const selfId = 'self';

  final AuraNode self;

  /// 나를 뺀 친구들의 오라입니다.
  final List<AuraNode> nodes;
  final List<AuraLink> links;

  /// 이번 갱신에서 나와 새로 합쳐진 친구가 있으면 true입니다. 햅틱에 씁니다.
  final bool joinedSelf;

  /// 가장 가까운 친구까지의 실제 거리입니다. 위치 갱신 주기를 정할 때 씁니다.
  final double? nearestMeters;

  /// 지도에 그릴 것이 내 오라뿐이면 기존 테두리 표시만으로 충분합니다.
  bool get isSolo => nodes.isEmpty;

  /// [ids] 러너를 뺀 상태입니다. 함께 달리기 덩어리로 묶인 참여자를 뺄 때 씁니다.
  /// 남는 친구가 없으면 null입니다.
  CrewAuraState? without(Set<String> ids) {
    if (ids.isEmpty) return this;
    final kept = [
      for (final node in nodes)
        if (!ids.contains(node.id)) node,
    ];
    if (kept.isEmpty) return null;
    return CrewAuraState(
      self: self,
      nodes: kept,
      links: [
        for (final link in links)
          if (!ids.contains(link.a) && !ids.contains(link.b)) link,
      ],
      joinedSelf: joinedSelf,
      nearestMeters: nearestMeters,
    );
  }

  Map<String, Object?> toJson() => {
    // 지도는 이 거리 기준으로 빛줄기 굵기와 합쳐진 목의 굵기를 정합니다.
    'limits': {
      'merge': CrewAuraTracker.mergeMeters,
      'split': CrewAuraTracker.splitMeters,
      'beam': CrewAuraTracker.beamMeters,
    },
    'self': {'color': self.color, 'crew': self.crew, 'sync': self.inSync},
    'nodes': [
      for (final node in nodes)
        {
          'id': node.id,
          'point': [node.latitude, node.longitude],
          'color': node.color,
          'crew': node.crew,
          'sync': node.inSync,
        },
    ],
    'links': [
      for (final link in links)
        {
          'a': link.a,
          'b': link.b,
          // 작은 거리 흔들림으로 지도를 매번 다시 그리지 않도록 0.5m 단위로 보냅니다.
          'm': (link.meters * 2).round() / 2,
          'merged': link.merged,
        },
    ],
  };
}

/// 실제 GPS 거리(m)로 오라의 합체·분리를 판정합니다. 화면 배율은 쓰지 않습니다.
///
/// - 600m 이상: 각자 오라
/// - 600m 안: 빛줄기(가까울수록 굵게)
/// - 300m 이내로 들어오면 합체, 400m 밖으로 나가야 분리(경계에서 깜빡이지 않게 간격을 둠)
class CrewAuraTracker {
  CrewAuraTracker({this.window = const Duration(seconds: 6)});

  static const mergeMeters = 300.0;
  static const splitMeters = 400.0;
  static const beamMeters = 600.0;

  /// 페이스 차이가 이 값(초/km) 이내면 같은 박자로 맥동합니다.
  static const syncPaceSeconds = 10;

  /// 한 번에 그리는 친구 수입니다. 가까운 순서로 고릅니다.
  static const maxFriends = 6;

  /// 친구 위치를 평균 내는 시간 폭입니다. GPS가 순간적으로 튀는 값을 줄입니다.
  final Duration window;

  final _tracks = <String, List<_Sample>>{};
  final _merged = <String>{};

  static String _key(String a, String b) =>
      a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  /// 두 좌표 사이의 실제 거리(m)입니다.
  static double metersBetween(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const radius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * radius * math.asin(math.min(1, math.sqrt(a)));
  }

  ({double latitude, double longitude}) _smooth(AuraRunner runner) {
    final samples = _tracks.putIfAbsent(runner.id, () => []);
    if (samples.isEmpty || runner.at.isAfter(samples.last.at)) {
      samples.add(_Sample(runner.at, runner.latitude, runner.longitude));
    }
    // 가장 최근 위치를 기준으로 시간 폭 안의 값만 평균 냅니다. 최신 값 하나는 항상 남깁니다.
    final oldest = samples.last.at.subtract(window);
    samples.removeWhere((sample) => sample.at.isBefore(oldest));
    var latitude = 0.0, longitude = 0.0;
    for (final sample in samples) {
      latitude += sample.latitude;
      longitude += sample.longitude;
    }
    return (
      latitude: latitude / samples.length,
      longitude: longitude / samples.length,
    );
  }

  /// 오라를 끄거나 지도를 떠날 때 기록을 지웁니다.
  void reset() {
    _tracks.clear();
    _merged.clear();
  }

  CrewAuraState update({
    required AuraRunner self,
    required List<AuraRunner> friends,
  }) {
    final ids = {CrewAuraState.selfId, for (final friend in friends) friend.id};
    _tracks.removeWhere((id, _) => !ids.contains(id));

    // 내 위치도 같은 폭으로 평균 내어 친구와 같은 만큼만 늦게 따라가게 합니다.
    final me = _smooth(
      AuraRunner(
        id: CrewAuraState.selfId,
        latitude: self.latitude,
        longitude: self.longitude,
        at: self.at,
        color: self.color,
        paceSecPerKm: self.paceSecPerKm,
      ),
    );
    final smoothed = <String, ({double latitude, double longitude})>{};
    final fromMe = <String, double>{};
    for (final friend in friends) {
      final point = smoothed[friend.id] = _smooth(friend);
      fromMe[friend.id] = metersBetween(
        me.latitude,
        me.longitude,
        point.latitude,
        point.longitude,
      );
    }
    final nearest = fromMe.values.fold<double?>(
      null,
      (best, value) => best == null || value < best ? value : best,
    );

    // 빛줄기가 닿는 범위의 친구만, 가까운 순서로 그립니다.
    final near = friends.where((friend) {
      final meters = fromMe[friend.id]!;
      return meters < beamMeters ||
          _merged.contains(_key(CrewAuraState.selfId, friend.id));
    }).toList()..sort((a, b) => fromMe[a.id]!.compareTo(fromMe[b.id]!));
    final shown = near.take(maxFriends).toList();
    final shownIds = {CrewAuraState.selfId, for (final f in shown) f.id};
    _merged.removeWhere((key) => !key.split('|').every(shownIds.contains));

    final links = <AuraLink>[];
    var joinedSelf = false;
    void connect(String a, String b, double meters) {
      final key = _key(a, b);
      final wasMerged = _merged.contains(key);
      final merged = wasMerged ? meters <= splitMeters : meters <= mergeMeters;
      if (merged) {
        _merged.add(key);
        if (!wasMerged && (a == CrewAuraState.selfId)) joinedSelf = true;
      } else {
        _merged.remove(key);
      }
      if (merged || meters < beamMeters) {
        links.add(AuraLink(a, b, meters, merged: merged));
      }
    }

    for (var i = 0; i < shown.length; i++) {
      connect(CrewAuraState.selfId, shown[i].id, fromMe[shown[i].id]!);
      for (var j = i + 1; j < shown.length; j++) {
        final a = smoothed[shown[i].id]!, b = smoothed[shown[j].id]!;
        connect(
          shown[i].id,
          shown[j].id,
          metersBetween(a.latitude, a.longitude, b.latitude, b.longitude),
        );
      }
    }

    // 합쳐진 연결로 이어진 러너들을 한 무리로 묶습니다.
    final crewOf = <String, String>{for (final id in shownIds) id: id};
    String root(String id) {
      while (crewOf[id] != id) {
        id = crewOf[id] = crewOf[crewOf[id]!]!;
      }
      return id;
    }

    for (final link in links.where((link) => link.merged)) {
      final a = root(link.a), b = root(link.b);
      if (a != b) crewOf[b] = a;
    }
    final members = <String, List<String>>{};
    for (final id in shownIds) {
      members.putIfAbsent(root(id), () => []).add(id);
    }
    // 무리 번호는 무리마다 0부터 차례로 붙입니다.
    final crewNumber = <String, int>{};
    var next = 0;
    for (final group in members.values.where((group) => group.length > 1)) {
      for (final id in group) {
        crewNumber[id] = next;
      }
      next++;
    }

    // 무리의 기준 러너(내가 있으면 나)와 페이스가 비슷하면 같은 박자로 맥동합니다.
    final paces = <String, int?>{
      CrewAuraState.selfId: self.paceSecPerKm,
      for (final friend in shown) friend.id: friend.paceSecPerKm,
    };
    final inSync = <String, bool>{};
    for (final group in members.values) {
      final reference = group.contains(CrewAuraState.selfId)
          ? CrewAuraState.selfId
          : (group.toList()..sort()).first;
      for (final id in group) {
        final a = paces[reference], b = paces[id];
        inSync[id] =
            id == reference ||
            (a != null && b != null && (a - b).abs() <= syncPaceSeconds);
      }
    }

    return CrewAuraState(
      self: AuraNode(
        id: CrewAuraState.selfId,
        latitude: self.latitude,
        longitude: self.longitude,
        color: self.color,
        crew: crewNumber[CrewAuraState.selfId],
        inSync: true,
      ),
      nodes: [
        for (final friend in shown)
          AuraNode(
            id: friend.id,
            latitude: smoothed[friend.id]!.latitude,
            longitude: smoothed[friend.id]!.longitude,
            color: friend.color,
            crew: crewNumber[friend.id],
            inSync: inSync[friend.id] ?? true,
          ),
      ],
      links: links,
      joinedSelf: joinedSelf,
      nearestMeters: nearest,
    );
  }
}

class _Sample {
  const _Sample(this.at, this.latitude, this.longitude);
  final DateTime at;
  final double latitude;
  final double longitude;
}
