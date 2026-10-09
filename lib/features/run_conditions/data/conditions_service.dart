import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/running_conditions.dart';

abstract interface class ConditionsService {
  Future<RunningConditions> load(double latitude, double longitude);
}

class ConditionsFailure implements Exception {
  const ConditionsFailure(this.code);
  final String code;
  String get message => switch (code) {
    'unsupported_area' => '현재 지역의 날씨·미세먼지는 지원하지 않습니다.',
    'unauthorized' || 'forbidden' => '로그인 상태와 계정 이용 권한을 확인해 주세요.',
    'rate_limited' => '잠시 후 다시 조회해 주세요.',
    _ => '러닝 환경을 가져오지 못했습니다. 다시 시도해 주세요.',
  };
}

class SupabaseConditionsService implements ConditionsService {
  SupabaseConditionsService(this.client);
  final SupabaseClient client;

  @override
  Future<RunningConditions> load(double latitude, double longitude) async {
    try {
      final response = await client.functions
          .invoke(
            'running-conditions',
            body: {
              // 기상 격자와 주변 측정소 선택에 필요한 약 1km 정밀도만 전송합니다.
              'latitude': (latitude * 100).round() / 100,
              'longitude': (longitude * 100).round() / 100,
            },
          )
          .timeout(const Duration(seconds: 35));
      return RunningConditions.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on FunctionException catch (error) {
      final details = error.details;
      throw ConditionsFailure(
        details is Map && details['error'] is String
            ? details['error'] as String
            : 'unavailable',
      );
    } catch (_) {
      throw const ConditionsFailure('unavailable');
    }
  }
}
