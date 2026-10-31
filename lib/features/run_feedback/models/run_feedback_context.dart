import '../../run_history/models/run_analysis_data.dart';
import '../../run_history/models/run_split.dart';

class RunFeedbackContext {
  RunFeedbackContext({
    required this.startedAt,
    required this.splits,
    required this.analysis,
  });
  final DateTime startedAt;
  final List<RunSplit>? splits;
  final RunAnalysisData? analysis;

  factory RunFeedbackContext.fromJson(Map<String, dynamic> json) =>
      RunFeedbackContext(
        startedAt: DateTime.parse(json['started_at'] as String),
        splits: RunSplit.decode(json['split_data']),
        analysis: RunAnalysisData.decode(json['analysis_data']),
      );

  /// 활동 시각을 실제 시각에 연결합니다. 정지·복구 구간과 불연속 시각은 제외합니다.
  int? activeMilliseconds(DateTime from, DateTime to) {
    final start = from.difference(startedAt).inMilliseconds;
    final end = to.difference(startedAt).inMilliseconds;
    final windows = analysis?.windows;
    if (windows == null || windows.isEmpty) return null;
    var lower = 0, upper = windows.length;
    while (lower < upper) {
      final middle = (lower + upper) ~/ 2;
      if (windows[middle][0] <= start) {
        lower = middle + 1;
      } else {
        upper = middle;
      }
    }
    if (lower == 0) return null;
    final w = windows[lower - 1];
    if (start >= w[0] &&
        start < w[1] &&
        end <= w[1] &&
        end >= start &&
        w[1] > w[0] &&
        ((w[1] - w[0]) - (w[3] - w[2])).abs() <= 1000) {
      return (w[2] + (start - w[0]) * (w[3] - w[2]) / (w[1] - w[0])).round();
    }
    return null;
  }
}
