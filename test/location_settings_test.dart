import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:runquest/features/home/data/location_settings.dart';

void main() {
  test('Android 러닝만 지속 알림과 부분 실행 잠금을 사용합니다', () {
    final map = trackingSettings(
      platform: TargetPlatform.android,
      recording: false,
    ) as AndroidSettings;
    final run = trackingSettings(
      platform: TargetPlatform.android,
      recording: true,
    ) as AndroidSettings;
    expect(map.foregroundNotificationConfig, isNull);
    expect(run.intervalDuration, const Duration(seconds: 5));
    final notification = run.foregroundNotificationConfig!;
    expect(notification.enableWakeLock, isTrue);
    expect(notification.enableWifiLock, isFalse);
    expect(notification.setOngoing, isTrue);
    expect(notification.notificationTitle, '러닝 측정 중');
    expect(run.timeLimit, isNull);
  });

  test('iOS 러닝만 백그라운드 위치와 사용 표시를 활성화합니다', () {
    final map = trackingSettings(
      platform: TargetPlatform.iOS,
      recording: false,
    ) as AppleSettings;
    final run = trackingSettings(
      platform: TargetPlatform.iOS,
      recording: true,
    ) as AppleSettings;
    expect(map.allowBackgroundLocationUpdates, isFalse);
    expect(map.showBackgroundLocationIndicator, isFalse);
    expect(run.allowBackgroundLocationUpdates, isTrue);
    expect(run.showBackgroundLocationIndicator, isTrue);
    expect(run.pauseLocationUpdatesAutomatically, isFalse);
    expect(run.activityType, ActivityType.fitness);
    expect(run.accuracy, LocationAccuracy.high);
    expect(run.distanceFilter, 5);
    expect(run.timeLimit, isNull);
  });

  test('다른 플랫폼에는 모바일 전용 설정을 적용하지 않습니다', () {
    final settings = trackingSettings(
      platform: TargetPlatform.macOS,
      recording: true,
    );
    expect(settings, isNot(isA<AppleSettings>()));
    expect(settings, isNot(isA<AndroidSettings>()));
    expect(settings.timeLimit, isNull);
  });
}
