import 'package:flutter/material.dart';

import '../conditions_controller.dart';
import '../../../shared/theme/app_colors.dart';
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
      final color = switch (status) {
        RunningSuitability.good => const Color(0xFF18734A),
        RunningSuitability.caution => const Color(0xFF946100),
        RunningSuitability.avoid => const Color(0xFFB52C36),
        RunningSuitability.unknown => const Color(0xFF657079),
      };
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
        color: Colors.white,
        child: Container(
          decoration: const BoxDecoration(
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
                        const Text(
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
                        style: const TextStyle(
                          color: AppColors.gray,
                          fontSize: 13,
                        ),
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
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            freshWeather?.precipitation == null
                                ? '강수 --'
                                : freshWeather!.precipitationLabel,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '초미세 ${freshDust?.pm25 == null ? '--' : DustObservation.gradeLabel(DustObservation.grade(freshDust!.pm25, fine: true))}',
                            style: const TextStyle(
                              color: Color(0xFF475569),
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
                icon: const Icon(
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

  void _details(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme
              .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: AppColors.ink),
          child: SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.8,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final data = controller.data;
                  final assessment = data?.assess(controller.now);
                  final weather = data?.weather, dust = data?.dust;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '러닝 환경',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '새로고침',
                              onPressed: controller.loading
                                  ? null
                                  : controller.refresh,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        Text(
                          assessment?.label ?? '조건 판단 불가',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final note
                            in assessment?.notes ??
                                [controller.error ?? '현재 위치 확인 중'])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(note),
                          ),
                        if (assessment?.incomplete == true)
                          const Text('일부 자료가 없어 전체 조건은 확인할 수 없습니다.'),
                        const Divider(height: 28),
                        const Text(
                          '날씨',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        _value(
                          '기온',
                          '${weather?.temperature?.toStringAsFixed(1) ?? "—"} °C',
                        ),
                        _value(
                          '강수',
                          '${weather?.precipitationLabel ?? "자료 없음"} · ${weather?.rain?.toStringAsFixed(1) ?? "—"} mm/h',
                        ),
                        _value(
                          '바람',
                          '${weather?.wind?.toStringAsFixed(1) ?? "—"} m/s',
                        ),
                        Text(
                          '기상청 · 5km 격자 대표 관측 · ${_time(weather?.observedAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (data?.weatherError != null)
                          Text(
                            _providerError(
                              data!.weatherError!,
                              hasPrevious: weather != null,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (weather?.cachedAt != null)
                          Text(
                            _time(weather!.cachedAt, suffix: '서버 갱신'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        const Divider(height: 28),
                        const Text(
                          '미세먼지',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        _value(
                          '미세먼지',
                          '${dust?.pm10?.toStringAsFixed(0) ?? "—"} µg/m³ · ${DustObservation.gradeLabel(DustObservation.grade(dust?.pm10, fine: false))}',
                        ),
                        _value(
                          '초미세먼지',
                          '${dust?.pm25?.toStringAsFixed(0) ?? "—"} µg/m³ · ${DustObservation.gradeLabel(DustObservation.grade(dust?.pm25, fine: true))}',
                        ),
                        Text(
                          '한국환경공단 에어코리아 · ${_time(dust?.observedAt)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (dust != null)
                          Text(
                            '${dust.station} 측정소 · 약 ${dust.distanceKm.toStringAsFixed(1)}km',
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (data?.dustError != null)
                          Text(
                            _providerError(
                              data!.dustError!,
                              hasPrevious: dust != null,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        if (dust?.cachedAt != null)
                          Text(
                            _time(dust!.cachedAt, suffix: '서버 갱신'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        const Divider(height: 28),
                        const ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            '자료 안내',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            Text(
                              '관측 농도로 계산한 참고 등급이며 공식 예보나 특보가 아닙니다. 측정소와 현재 위치의 실제 대기질은 다를 수 있습니다. 건강 상태와 현장 상황도 확인해 주세요.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.gray,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '앱 주의 기준: 기온 0°C 이하·30°C 이상, 바람 8m/s 이상, 강수 관측. 미세먼지 두 항목 중 더 나쁜 농도 등급을 반영합니다. 관측 후 2시간이 넘으면 전체 조건을 판단하지 않습니다.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.gray,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 84, child: Text(label)),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
  String _time(DateTime? time, {String suffix = '관측'}) {
    if (time == null) return '관측 시각 없음';
    final local = time.toLocal();
    return '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $suffix';
  }

  String _providerError(String code, {bool hasPrevious = false}) =>
      switch (code) {
        'quota_exhausted' =>
          hasPrevious
              ? '공동 조회 한도에 도달하여 마지막 관측 자료를 표시합니다.'
              : '공동 조회 한도에 도달했고 저장된 관측 자료가 없습니다.',
        'refresh_in_progress' => '같은 지역의 관측 자료를 공동 갱신하고 있습니다.',
        'refresh_superseded' => '지역 관측 자료 갱신을 다시 확인해야 합니다.',
        'cache_unavailable' => '관측 자료 저장소에 연결하지 못했습니다.',
        'permission_denied' => '관측 API 이용 권한을 확인해야 합니다.',
        'no_nearby_station' => '30km 안에 두 미세먼지 항목을 측정하는 측정소가 없습니다.',
        'not_configured' => '서버의 관측 API 설정이 필요합니다.',
        _ => '관측 기관의 자료를 가져오지 못했습니다.',
      };
}
