import 'package:flutter/material.dart';
import 'package:runquest/features/course/models/route_plan.dart';
import 'package:runquest/features/course/models/run_preset.dart';
import 'package:runquest/features/course/widgets/choice_menu.dart';
import 'package:runquest/features/course/widgets/preset_grid.dart';
import 'package:runquest/features/course/widgets/route_cards.dart';
import 'package:runquest/shared/widgets/page_layout.dart';

class CourseScreen extends StatelessWidget {
  const CourseScreen({
    required this.plan,
    required this.distance,
    required this.slope,
    required this.flow,
    required this.environment,
    required this.safety,
    required this.onDistance,
    required this.onSlope,
    required this.onFlow,
    required this.onEnvironment,
    required this.onSafety,
    required this.onPresetTap,
    super.key,
  });

  final RoutePlan plan;
  final String distance;
  final String slope;
  final String flow;
  final String environment;
  final String safety;
  final ValueChanged<String> onDistance;
  final ValueChanged<String> onSlope;
  final ValueChanged<String> onFlow;
  final ValueChanged<String> onEnvironment;
  final ValueChanged<String> onSafety;
  final ValueChanged<RunPreset> onPresetTap;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '코스 만들기', subtitle: '5가지만 고르면 추천 완료'),
          const SizedBox(height: 12),
          ChoiceMenu(
            label: '거리',
            selected: distance,
            options: const ['3 km', '5 km', '7 km', '10 km'],
            onChanged: onDistance,
          ),
          ChoiceMenu(
            label: '경사',
            selected: slope,
            options: const ['평지 위주', '완만한 경사', '업힐 도전'],
            onChanged: onSlope,
          ),
          ChoiceMenu(
            label: '흐름',
            selected: flow,
            options: const ['페이스 유지', '여유런', '신호 적게'],
            onChanged: onFlow,
          ),
          ChoiceMenu(
            label: '환경',
            selected: environment,
            options: const ['도심', '공원/하천', '혼합'],
            onChanged: onEnvironment,
          ),
          ChoiceMenu(
            label: '안전',
            selected: safety,
            options: const ['최적 경로', '골목길 회피', '야간 안전'],
            onChanged: onSafety,
          ),
          const SizedBox(height: 8),
          Text('프리셋', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Expanded(flex: 5, child: PresetGrid(onPresetTap: onPresetTap)),
          const SizedBox(height: 10),
          Expanded(flex: 5, child: CompactPlanCard(plan: plan)),
        ],
      ),
    );
  }
}
