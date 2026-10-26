class RunMotionEvidence {
  const RunMotionEvidence({
    required this.startSeconds,
    required this.endSeconds,
    required this.speedKmh,
    required this.accuracyMeters,
  });
  final double startSeconds;
  final double endSeconds;
  final double speedKmh;
  final double accuracyMeters;

  static List<RunMotionEvidence>? decode(Object? data) => data == null
      ? null
      : List.unmodifiable(
          (data as List).map((value) {
            final item = value as Map;
            return RunMotionEvidence(
              startSeconds: (item['start_s'] as num).toDouble(),
              endSeconds: (item['end_s'] as num).toDouble(),
              speedKmh: (item['speed_kmh'] as num).toDouble(),
              accuracyMeters: (item['accuracy_m'] as num).toDouble(),
            );
          }),
        );
}
