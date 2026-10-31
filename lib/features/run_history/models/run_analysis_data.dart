/// 좌표·건강 원시 표본 없이 보존하는 러닝 분석 자료입니다.
class RunAnalysisData {
  RunAnalysisData({
    required this.windows,
    required this.pauses,
    required this.elevation,
    required this.gps,
  });
  // 실제 경과 시작·끝(ms), 활동 시간 시작·끝(ms)입니다.
  final List<List<num>> windows;
  // 실제 경과 시작·끝(ms), 사유(0: 사용자, 1: GPS, 2: 복구, 3: 화면 종료)입니다.
  final List<List<num>> pauses;
  // 누적 거리 시작·끝(m), 고도 차이(m), 수직 오차 합(m)입니다.
  final List<List<num>> elevation;
  // km 번호, 수신 수, 제외 수, 단절 수, 단절 시간(ms), 정확도 합·최대(m), 정확도 표본 수입니다.
  final List<List<num>> gps;

  Map<String, Object> toJson() => {
    'version': 1,
    'windows': windows,
    'pauses': pauses,
    'elevation': elevation,
    'gps': gps,
  };

  static RunAnalysisData? decode(Object? value) {
    if (value == null) return null;
    if (value is! Map || value['version'] != 1) {
      throw const FormatException('분석 자료 형식이 올바르지 않습니다.');
    }
    List<List<num>> rows(String key, int width, int limit) {
      final items = value[key];
      if (items is! List || items.length > limit) {
        throw const FormatException('분석 자료 크기가 올바르지 않습니다.');
      }
      return List.unmodifiable(
        items.map((row) {
          if (row is! List ||
              row.length != width ||
              row.any((n) => n is! num || !n.isFinite)) {
            throw const FormatException('분석 측정값이 올바르지 않습니다.');
          }
          return List<num>.unmodifiable(row.cast<num>());
        }),
      );
    }

    final result = RunAnalysisData(
      windows: rows('windows', 4, 10000),
      pauses: rows('pauses', 3, 10000),
      elevation: rows('elevation', 4, 100000),
      gps: rows('gps', 8, 1001),
    );
    num lastWall = 0, lastActive = 0;
    for (final w in result.windows) {
      if (w[0] < lastWall ||
          w[1] < w[0] ||
          w[2] < lastActive ||
          w[3] < w[2] ||
          w[1] > 604800000 ||
          w[3] > 604800000) {
        throw const FormatException('활동 시간 구간이 올바르지 않습니다.');
      }
      lastWall = w[1];
      lastActive = w[3];
    }
    for (final p in result.pauses) {
      if (p[0] < 0 ||
          p[1] < p[0] ||
          p[1] > 604800000 ||
          p[2] < 0 ||
          p[2] > 3 ||
          p[2] != p[2].round()) {
        throw const FormatException('중단 구간이 올바르지 않습니다.');
      }
    }
    for (final e in result.elevation) {
      if (e[0] < 0 ||
          e[1] <= e[0] ||
          e[1] > 1000000 ||
          e[2].abs() > 20000 ||
          e[3] <= 0 ||
          e[3] > 20) {
        throw const FormatException('고도 구간이 올바르지 않습니다.');
      }
    }
    for (final g in result.gps) {
      if (g[0] < 1 ||
          g[0] > 1001 ||
          g[1] < 0 ||
          g[2] < 0 ||
          g[2] > g[1] ||
          g[3] < 0 ||
          g[4] < 0 ||
          g[5] < 0 ||
          g[6] < 0 ||
          g[7] < 0 || g[7] > g[1] ||
          g.any((n) => n > 1e12)) {
        throw const FormatException('위치 품질 자료가 올바르지 않습니다.');
      }
    }
    return result;
  }
}
