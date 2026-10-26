import 'dart:convert';

import 'package:health/health.dart';

class RunHealthSource {
  const RunHealthSource({
    required this.id,
    required this.label,
    required this.heartSamples,
    this.averageHeartRate,
    this.maxHeartRate,
    this.activeCalories,
    this.overlappingCalories = false,
  });
  final String id;
  final String label;
  final int heartSamples;
  final double? averageHeartRate;
  final double? maxHeartRate;
  final double? activeCalories;
  final bool overlappingCalories;
}

class RunHealthData {
  const RunHealthData(this.sources, {this.notices = const []});
  final List<RunHealthSource> sources;
  final List<String> notices;
}

RunHealthData summarizeRunHealth(
  List<HealthDataPoint> points,
  DateTime start,
  DateTime end, {
  List<String> notices = const [],
}) {
  final sources = <String, List<HealthDataPoint>>{};
  final seen = <String>{};
  for (final point in points) {
    final value = point.value;
    if (value is! NumericHealthValue ||
        !value.numericValue.isFinite ||
        point.recordingMethod == RecordingMethod.manual ||
        point.dateFrom.isBefore(start) ||
        point.dateTo.isAfter(end) ||
        !point.dateFrom.isBefore(end) ||
        point.dateTo.isBefore(point.dateFrom) ||
        (point.sourceId.isEmpty && point.sourceName.isEmpty)) {
      continue;
    }
    if (point.type != HealthDataType.HEART_RATE &&
        point.type != HealthDataType.ACTIVE_ENERGY_BURNED) {
      continue;
    }
    if (value.numericValue < 0 ||
        (point.type == HealthDataType.HEART_RATE && value.numericValue == 0)) {
      continue;
    }
    final source = jsonEncode([
      point.sourceId,
      point.sourceName,
      point.sourceDeviceId,
      point.deviceModel,
    ]);
    final key = jsonEncode([
      source,
      point.type.name,
      point.uuid,
      point.dateFrom.toIso8601String(),
      point.dateTo.toIso8601String(),
      value.numericValue,
    ]);
    if (!seen.add(key)) continue;
    sources.putIfAbsent(source, () => []).add(point);
  }
  final result = <RunHealthSource>[];
  for (final entry in sources.entries) {
    final heart = entry.value
        .where((point) => point.type == HealthDataType.HEART_RATE)
        .map(
          (point) =>
              (point.value as NumericHealthValue).numericValue.toDouble(),
        )
        .toList();
    final calories =
        entry.value
            .where((point) => point.type == HealthDataType.ACTIVE_ENERGY_BURNED)
            .toList()
          ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    var overlaps = false;
    DateTime? previousEnd;
    for (final point in calories) {
      if (previousEnd != null && point.dateFrom.isBefore(previousEnd)) {
        overlaps = true;
      }
      if (previousEnd == null || point.dateTo.isAfter(previousEnd)) {
        previousEnd = point.dateTo;
      }
    }
    final first = entry.value.first;
    final label = [
      first.sourceName.isNotEmpty ? first.sourceName : first.sourceId,
      if (first.deviceModel?.isNotEmpty == true) first.deviceModel!,
    ].join(' · ');
    result.add(
      RunHealthSource(
        id: entry.key,
        label: label,
        heartSamples: heart.length,
        averageHeartRate: heart.isEmpty
            ? null
            : heart.reduce((a, b) => a + b) / heart.length,
        maxHeartRate: heart.isEmpty
            ? null
            : heart.reduce((a, b) => a > b ? a : b),
        activeCalories: calories.isEmpty || overlaps
            ? null
            : calories.fold<double>(
                0,
                (sum, point) =>
                    sum + (point.value as NumericHealthValue).numericValue,
              ),
        overlappingCalories: overlaps,
      ),
    );
  }
  result.sort((a, b) => a.id.compareTo(b.id));
  return RunHealthData(
    List.unmodifiable(result),
    notices: List.unmodifiable(notices),
  );
}
