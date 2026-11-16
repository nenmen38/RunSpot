import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

LocationSettings trackingSettings({
  required TargetPlatform platform,
  required bool recording,
}) {
  if (platform == TargetPlatform.android) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      // 러닝 중에는 멈춰 있어도 위치를 계속 받아야 신호가 끊긴 것으로 오해하지 않습니다.
      distanceFilter: recording ? 0 : 5,
      intervalDuration: Duration(seconds: recording ? 2 : 5),
      foregroundNotificationConfig: recording
          ? const ForegroundNotificationConfig(
              notificationTitle: '러닝 측정 중',
              notificationText: '화면이 꺼져도 러닝 거리와 시간을 측정합니다.',
              notificationChannelName: '러닝 측정',
              enableWakeLock: true,
              setOngoing: true,
            )
          : null,
    );
  }
  if (platform == TargetPlatform.iOS) {
    return AppleSettings(
      accuracy: recording
          ? LocationAccuracy.bestForNavigation
          : LocationAccuracy.high,
      distanceFilter: recording ? 0 : 5,
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: recording,
      showBackgroundLocationIndicator: recording,
    );
  }
  return const LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );
}
