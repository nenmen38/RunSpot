class RunSplit {
  const RunSplit({required this.distanceMeters, required this.duration});
  final double distanceMeters;
  final Duration duration;
  double get speedKmh => duration.inMicroseconds > 0
      ? distanceMeters * 3600000 / duration.inMicroseconds
      : 0;
  Duration? get pace => distanceMeters > 0 && duration.inMicroseconds > 0
      ? Duration(
          microseconds: (duration.inMicroseconds * 1000 / distanceMeters)
              .round(),
        )
      : null;
  Map<String, Object> toJson() => {
    'distance_m': distanceMeters,
    'duration_us': duration.inMicroseconds,
  };
  factory RunSplit.fromJson(Map<String, dynamic> json) {
    final distance = json['distance_m'];
    final micros = json['duration_us'];
    if (distance is! num ||
        !distance.isFinite ||
        distance <= 0 ||
        distance > 1000 ||
        micros is! num ||
        !micros.isFinite ||
        micros < 0 ||
        micros > 604800000000 ||
        micros != micros.truncateToDouble()) {
      throw const FormatException('구간 기록이 올바르지 않습니다.');
    }
    return RunSplit(
      distanceMeters: distance.toDouble(),
      duration: Duration(microseconds: micros.toInt()),
    );
  }
  static bool matches(
    List<RunSplit>? splits,
    double distance,
    Duration duration,
  ) {
    if (splits == null) return true;
    if (splits.isEmpty) return distance == 0;
    if (splits.length > 1001) return false;
    var metres = 0.0;
    var micros = 0;
    for (var i = 0; i < splits.length; i++) {
      final split = splits[i];
      if (!split.distanceMeters.isFinite ||
          split.distanceMeters <= 0 ||
          split.distanceMeters > 1000 ||
          split.duration.isNegative ||
          (i < splits.length - 1 && split.distanceMeters != 1000)) {
        return false;
      }
      metres += split.distanceMeters;
      micros += split.duration.inMicroseconds;
    }
    return (metres - distance).abs() < 0.000001 &&
        micros == duration.inMicroseconds;
  }

  static List<RunSplit>? decode(Object? value) {
    if (value == null) return null;
    if (value is! List || value.length > 1001) {
      throw const FormatException('구간 기록이 올바르지 않습니다.');
    }
    return List.unmodifiable(
      value.map(
        (row) => RunSplit.fromJson(Map<String, dynamic>.from(row as Map)),
      ),
    );
  }
}
