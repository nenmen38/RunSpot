import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/course/course_controller.dart';
import 'package:runquest/features/course/data/presets.dart';

void main() {
  test('기본 코스 계산 결과를 유지합니다', () {
    final controller = CourseController();
    addTearDown(controller.dispose);
    expect(controller.plan.title, '5K 공원·하천 페이스유지');
    expect(controller.plan.mission, '마지막 700m 가속');
    expect(controller.plan.scores, {'안전': 84, '흐름': 82, '경사': 88, '환경': 94});
  });

  test('부분 변경은 나머지 선택을 유지하고 한 번 알립니다', () {
    final controller = CourseController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.updatePlan(distance: '10 km');
    expect(controller.distance, '10 km');
    expect(controller.environment, '공원/하천');
    expect(controller.safety, '골목길 회피');
    expect(controller.plan.mission, '마지막 2km 페이스 유지');
    expect(notifications, 1);
  });

  test('모든 프리셋의 선택과 점수를 유지합니다', () {
    final controller = CourseController();
    addTearDown(controller.dispose);
    final expected = [
      ['5 km', '평지 위주', '여유런', '혼합', '야간 안전', 90, 72, 88, 78],
      ['5 km', '평지 위주', '신호 적게', '도심', '최적 경로', 76, 86, 88, 64],
      ['7 km', '업힐 도전', '여유런', '도심', '골목길 회피', 84, 72, 92, 64],
      ['5 km', '완만한 경사', '여유런', '공원/하천', '최적 경로', 76, 72, 76, 94],
      ['10 km', '평지 위주', '신호 적게', '도심', '최적 경로', 76, 86, 88, 64],
    ];
    for (var i = 0; i < presets.length; i++) {
      controller.applyPreset(presets[i]);
      expect([
        controller.distance,
        controller.slope,
        controller.flow,
        controller.environment,
        controller.safety,
        ...controller.plan.scores.values,
      ], expected[i]);
    }
  });
}
