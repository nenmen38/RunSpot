import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../models/run_health_data.dart';

abstract interface class RunHealthService {
  Future<void> requestAccess();
  Future<RunHealthData> read(
    DateTime start,
    DateTime end, {
    bool Function()? canRead,
  });
}

class HealthAccessException implements Exception {
  const HealthAccessException(this.message);
  final String message;
}

class DeviceRunHealthService implements RunHealthService {
  DeviceRunHealthService({Health? health}) : _health = health ?? Health();
  final Health _health;
  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  static const _types = [
    HealthDataType.HEART_RATE,
    HealthDataType.ACTIVE_ENERGY_BURNED,
  ];

  Future<void> _prepare() async {
    if (kIsWeb || (!_android && defaultTargetPlatform != TargetPlatform.iOS)) {
      throw const HealthAccessException('건강 데이터는 아이폰·안드로이드 앱에서 연결해 주세요.');
    }
    await _health.configure();
    if (_android &&
        await _health.getHealthConnectSdkStatus() !=
            HealthConnectSdkStatus.sdkAvailable) {
      throw const HealthAccessException(
        '이 기기에서 헬스 커넥트를 사용할 수 없습니다. 설치·업데이트와 지원 여부를 확인해 주세요.',
      );
    }
  }

  @override
  Future<void> requestAccess() async {
    await _prepare();
    // 읽기만 요청하며 쓰기·전체 과거 이력·백그라운드 접근은 요청하지 않습니다.
    await _health.requestAuthorization(
      _types,
      permissions: const [HealthDataAccess.READ, HealthDataAccess.READ],
    );
  }

  @override
  Future<RunHealthData> read(
    DateTime start,
    DateTime end, {
    bool Function()? canRead,
  }) async {
    if (canRead?.call() == false) {
      throw const HealthAccessException('건강 데이터 조회를 중단했습니다.');
    }
    await _prepare();
    if (!end.isAfter(start) ||
        end.difference(start) > const Duration(days: 7)) {
      throw const HealthAccessException('조회할 러닝의 시작·종료 시각을 확인해 주세요.');
    }
    final points = <HealthDataPoint>[];
    final notices = <String>[];
    for (final type in _types) {
      if (canRead?.call() == false) break;
      final label = type == HealthDataType.HEART_RATE ? '심박수' : '활동 칼로리';
      try {
        if (_android &&
            await _health.hasPermissions(
                  [type],
                  permissions: [HealthDataAccess.READ],
                ) !=
                true) {
          notices.add('$label 읽기 권한이 없습니다.');
          continue;
        }
        if (canRead?.call() == false) break;
        points.addAll(
          await _health.getHealthDataFromTypes(
            types: [type],
            startTime: start,
            endTime: end,
            recordingMethodsToFilter: [RecordingMethod.manual],
          ),
        );
      } catch (_) {
        notices.add('$label 자료를 읽지 못했습니다. 권한과 기기 동기화를 확인해 주세요.');
      }
    }
    return summarizeRunHealth(points, start, end, notices: notices);
  }
}
