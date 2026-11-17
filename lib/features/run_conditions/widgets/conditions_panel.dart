import 'package:flutter/material.dart';

import '../conditions_controller.dart';
import '../../../shared/theme/app_colors.dart';
import 'conditions_details_sheet.dart';
import '../models/running_conditions.dart';

class ConditionsPanel extends StatelessWidget {
  const ConditionsPanel({required this.controller, super.key});
  final ConditionsController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = controller.data;
      final assessment = data?.assess(controller.now);
      final status = assessment?.status ?? RunningSuitability.unknown;
      final color = suitabilityColor(status);
      final weather = data?.weather, dust = data?.dust;
      final freshWeather =
          RunningConditions.isFresh(weather?.observedAt, controller.now)
          ? weather
          : null;
      final freshDust =
          RunningConditions.isFresh(dust?.observedAt, controller.now)
          ? dust
          : null;
      final label = switch (status) {
        RunningSuitability.good => '양호',
        RunningSuitability.caution => '주의',
        RunningSuitability.avoid => '야외 러닝 자제',
        RunningSuitability.unknown => '확인 필요',
      };
      return Material(
        color: AppColors.surface,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '러닝 환경',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            child: Text(
                              controller.loading && data == null
                                  ? '갱신 중'
                                  : label,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    if (data == null)
                      Text(
                        controller.loading ? '불러오는 중' : '자료 없음',
                        style: TextStyle(color: AppColors.gray, fontSize: 13),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            freshWeather?.temperature == null
                                ? '--'
                                : '${freshWeather!.temperature!.toStringAsFixed(1)}°C',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            freshWeather?.precipitation == null
                                ? '강수 --'
                                : freshWeather!.precipitationLabel,
                            style: TextStyle(
                              color: AppColors.gray,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '초미세 ${freshDust?.pm25 == null ? '--' : DustObservation.gradeLabel(DustObservation.grade(freshDust!.pm25, fine: true))}',
                            style: TextStyle(
                              color: AppColors.gray,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '러닝 환경 상세',
                onPressed: () => _details(context),
                icon: Icon(
                  Icons.chevron_right,
                  color: AppColors.gray,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  void _details(BuildContext context) =>
      showConditionsDetails(context, controller);
}

/// 러닝 환경 판단 색입니다. 다크 모드에서는 어두운 배경에서도 읽히도록 밝은 색을 씁니다.
Color suitabilityColor(RunningSuitability status) => switch (status) {
  RunningSuitability.good =>
    AppColors.dark ? const Color(0xFF4ED18F) : const Color(0xFF18734A),
  RunningSuitability.caution =>
    AppColors.dark ? const Color(0xFFF2B640) : const Color(0xFF946100),
  RunningSuitability.avoid =>
    AppColors.dark ? const Color(0xFFFF7B85) : const Color(0xFFB52C36),
  RunningSuitability.unknown => AppColors.gray,
};
