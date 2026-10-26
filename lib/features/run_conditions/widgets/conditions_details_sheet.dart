import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../conditions_controller.dart';
import '../models/running_conditions.dart';

void showConditionsDetails(
  BuildContext context,
  ConditionsController controller,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    builder: (context) => SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final data = controller.data;
          final assessment = data?.assess(controller.now);
          final weather =
              RunningConditions.isFresh(
                data?.weather?.observedAt,
                controller.now,
              )
              ? data?.weather
              : null;
          final dust =
              RunningConditions.isFresh(data?.dust?.observedAt, controller.now)
              ? data?.dust
              : null;
          final status = assessment?.status ?? RunningSuitability.unknown;
          final color = switch (status) {
            RunningSuitability.good => const Color(0xFF18734A),
            RunningSuitability.caution => const Color(0xFF946100),
            RunningSuitability.avoid => const Color(0xFFB52C36),
            RunningSuitability.unknown => AppColors.gray,
          };
          final label = switch (status) {
            RunningSuitability.good => '양호',
            RunningSuitability.caution => '주의',
            RunningSuitability.avoid => '야외 러닝 자제',
            RunningSuitability.unknown => '확인 필요',
          };
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '러닝 환경',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '관측 정보',
                      icon: const Icon(
                        Icons.info_outline,
                        size: 20,
                        color: AppColors.gray,
                      ),
                      onPressed: () => _showObservationInfo(context, data),
                    ),
                    IconButton(
                      tooltip: '새로고침',
                      onPressed: controller.loading ? null : controller.refresh,
                      icon: const Icon(
                        Icons.refresh,
                        size: 20,
                        color: AppColors.gray,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        weather?.temperature == null
                            ? '--'
                            : '${weather!.temperature!.toStringAsFixed(1)}°C',
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _precipitation(weather),
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 14,
                  ),
                ),
                if (controller.loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ] else if (assessment?.incomplete == true || data == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    data?.refreshNotice != null ? '최신 정보 확인 필요' : '일부 정보 없음',
                    style: const TextStyle(color: AppColors.gray, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 24),
                _ConditionRow(
                  icon: Icons.air,
                  label: '바람',
                  value: weather?.wind == null
                      ? '--'
                      : '${weather!.wind!.toStringAsFixed(1)} m/s',
                ),
                const Divider(height: 24, color: AppColors.line),
                _ConditionRow(
                  icon: Icons.blur_on,
                  label: '미세먼지',
                  value: _dust(dust?.pm10, fine: false),
                ),
                const Divider(height: 24, color: AppColors.line),
                _ConditionRow(
                  icon: Icons.grain,
                  label: '초미세먼지',
                  value: _dust(dust?.pm25, fine: true),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    ),
  );
}

String _precipitation(WeatherObservation? weather) {
  if (weather?.precipitation == null) return '강수 --';
  final rain = weather?.rain;
  return '${weather!.precipitationLabel}${rain != null && rain > 0 ? ' · ${rain.toStringAsFixed(1)} mm/h' : ''}';
}

String _dust(double? value, {required bool fine}) => value == null
    ? '--'
    : '${DustObservation.gradeLabel(DustObservation.grade(value, fine: fine))} · ${value.toStringAsFixed(0)} µg/m³';

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: AppColors.gray),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF475569), fontSize: 14),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        fit: FlexFit.tight,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

void _showObservationInfo(BuildContext context, RunningConditions? data) {
  String time(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('관측 정보'),
      content: Text(
        '날씨 · 기상청\n${time(data?.weather?.observedAt)}\n\n'
        '공기질 · 에어코리아\n${time(data?.dust?.observedAt)}\n\n'
        '${data?.refreshNotice != null ? '최근 갱신 실패\n\n' : ''}'
        '관측값 기준의 참고 정보이며 현재 위치의 실제 환경과 다를 수 있습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}
