import 'run_split.dart';

// 기존 이상 속도 기준과 보상 최소 거리 기준을 구간에도 동일하게 적용합니다.
class RunIntegrity {
  static const speedLimitMetersPerSecond = 6.5;
  static const minimumSegmentMeters = 300.0;

  static bool suspicious(RunSplit split) =>
      split.distanceMeters >= minimumSegmentMeters &&
      (split.duration.inMicroseconds <= 0 ||
          split.distanceMeters * 1000000 / split.duration.inMicroseconds >
              speedLimitMetersPerSecond);
}
