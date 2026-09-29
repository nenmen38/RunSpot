import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'models/route_plan.dart';
import 'models/run_preset.dart';

class CourseController extends ChangeNotifier {
  CourseController() {
    _plan = _makePlan();
  }
  String _distance = '5 km';
  String _slope = '평지 위주';
  String _flow = '페이스 유지';
  String _environment = '공원/하천';
  String _safety = '골목길 회피';
  late RoutePlan _plan;
  String get distance => _distance;
  String get slope => _slope;
  String get flow => _flow;
  String get environment => _environment;
  String get safety => _safety;
  RoutePlan get plan => _plan;

  RoutePlan _makePlan() {
    final distanceNumber = int.parse(_distance.split(' ').first);
    final safetyScore =
        76 + (_safety == '야간 안전' ? 14 : 0) + (_safety == '골목길 회피' ? 8 : 0);
    final flowScore =
        72 + (_flow == '신호 적게' ? 14 : 0) + (_flow == '페이스 유지' ? 10 : 0);
    final slopeScore = _slope == '업힐 도전' ? 92 : (_slope == '완만한 경사' ? 76 : 88);
    final natureScore = _environment == '공원/하천'
        ? 94
        : (_environment == '혼합' ? 78 : 64);

    return RoutePlan(
      title:
          '${distanceNumber}K ${_environment.replaceAll('/', '·')} ${_flow.replaceAll(' ', '')}',
      distance: _distance,
      slope: _slope,
      flow: _flow,
      environment: _environment,
      safety: _safety,
      mission: distanceNumber >= 10 ? '마지막 2km 페이스 유지' : '마지막 700m 가속',
      scores: {
        '안전': math.min(safetyScore, 98),
        '흐름': math.min(flowScore, 98),
        '경사': slopeScore,
        '환경': natureScore,
      },
    );
  }

  void updatePlan({
    String? distance,
    String? slope,
    String? flow,
    String? environment,
    String? safety,
  }) {
    _distance = distance ?? _distance;
    _slope = slope ?? _slope;
    _flow = flow ?? _flow;
    _environment = environment ?? _environment;
    _safety = safety ?? _safety;
    _plan = _makePlan();
    notifyListeners();
  }

  void applyPreset(RunPreset preset) {
    switch (preset.name) {
      case '야간 안전런':
        updatePlan(
          distance: '5 km',
          slope: '평지 위주',
          flow: '여유런',
          environment: '혼합',
          safety: '야간 안전',
        );
      case '페이스런':
        updatePlan(
          distance: '5 km',
          slope: '평지 위주',
          flow: '신호 적게',
          environment: '도심',
          safety: '최적 경로',
        );
      case '업힐런':
        updatePlan(
          distance: '7 km',
          slope: '업힐 도전',
          flow: '여유런',
          environment: '도심',
          safety: '골목길 회피',
        );
      case '힐링런':
        updatePlan(
          distance: '5 km',
          slope: '완만한 경사',
          flow: '여유런',
          environment: '공원/하천',
          safety: '최적 경로',
        );
      default:
        updatePlan(
          distance: '10 km',
          slope: '평지 위주',
          flow: '신호 적게',
          environment: '도심',
          safety: '최적 경로',
        );
    }
  }
}
