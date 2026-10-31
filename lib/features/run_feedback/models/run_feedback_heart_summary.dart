import 'run_feedback_context.dart';
import '../../health/models/run_health_data.dart';

/// 동의한 요청에만 포함하는 심박 숫자 요약입니다. 원시 표본과 기기 식별자는 제외합니다.
class RunFeedbackHeartSummary {
  const RunFeedbackHeartSummary._(
    this.averageBpm,
    this.maxBpm,
    this.sampleCount,
    this.segments,
  );

  final int averageBpm;
  final int maxBpm;
  final int sampleCount;
  final List<Map<String, int>> segments;

  static RunFeedbackHeartSummary? fromSource(
    RunHealthSource? source, {
    RunFeedbackContext? context,
  }) {
    final average = source?.averageHeartRate;
    final maximum = source?.maxHeartRate;
    if (source == null ||
        average == null ||
        maximum == null ||
        !average.isFinite ||
        !maximum.isFinite ||
        average < 1 ||
        maximum > 1000 ||
        average > maximum ||
        source.heartSamples < 1 ||
        source.heartSamples > 100000000) {
      return null;
    }
    final grouped = <int, List<double>>{};
    final splits = context?.splits;
    if (context != null && context.analysis != null && splits != null) {
      final boundaries = <int>[];
      var elapsed = 0;
      for (final split in splits) {
        elapsed += split.duration.inMilliseconds;
        boundaries.add(elapsed);
      }
      for (final point in source.heartObservations) {
        if (!point.bpm.isFinite || point.bpm < 1 || point.bpm > 1000) continue;
        final active = context.activeMilliseconds(point.start, point.end);
        final activeEnd = context.activeMilliseconds(point.end, point.end);
        if (active == null || activeEnd == null) continue;
        var lower = 0, upper = boundaries.length;
        while (lower < upper) {
          final middle = (lower + upper) ~/ 2;
          if (boundaries[middle] <= active) {
            lower = middle + 1;
          } else {
            upper = middle;
          }
        }
        final index = lower;
        if (index >= boundaries.length || activeEnd >= boundaries[index]) {
          continue;
        }
        grouped.putIfAbsent(index + 1, () => []).add(point.bpm);
      }
    }
    return RunFeedbackHeartSummary._(
      average.round(),
      maximum.round(),
      source.heartSamples,
      List.unmodifiable(
        grouped.entries.map(
          (entry) => {
            'index': entry.key,
            'average_bpm':
                (entry.value.reduce((a, b) => a + b) / entry.value.length)
                    .round(),
            'max_bpm': entry.value.reduce((a, b) => a > b ? a : b).round(),
            'sample_count': entry.value.length,
          },
        ),
      ),
    );
  }

  Map<String, Object> toJson() => {
    'average_bpm': averageBpm,
    'max_bpm': maxBpm,
    'sample_count': sampleCount,
    if (segments.isNotEmpty) 'segments': segments,
  };
}
