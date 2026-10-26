import 'dart:async';

import 'package:flutter/material.dart';

import '../data/run_health_service.dart';
import '../models/run_health_data.dart';
import '../../../shared/widgets/metric_values.dart';
import '../../../shared/theme/app_colors.dart';

const healthPrivacyNotice =
    '본인 기기의 심박·칼로리 자료를 불러옵니다. 자료는 화면에서만 사용하며 서버에 저장하지 않습니다.';

Future<bool> confirmHealthAccess(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('건강 데이터 연동'),
        content: const Text(healthPrivacyNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('계속'),
          ),
        ],
      ),
    ) ==
    true;

class RunHealthPanel extends StatefulWidget {
  const RunHealthPanel({
    required this.service,
    required this.start,
    required this.end,
    required this.isCurrentOwner,
    super.key,
  });
  final RunHealthService service;
  final DateTime start;
  final DateTime end;
  final bool Function() isCurrentOwner;
  @override
  State<RunHealthPanel> createState() => _RunHealthPanelState();
}

class _RunHealthPanelState extends State<RunHealthPanel>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _foreground = true;
  int _generation = 0;
  RunHealthData? _data;
  String? _selected;
  String? _error;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_load());
    } else {
      _generation++;
      setState(() {
        _data = null;
        _selected = null;
        _busy = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant RunHealthPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start ||
        oldWidget.end != widget.end ||
        oldWidget.service != widget.service) {
      _generation++;
      _data = null;
      _selected = null;
      _error = null;
      _busy = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_load());
      });
    }
  }

  Future<void> _load() async {
    if (_busy || !_foreground || !widget.isCurrentOwner()) {
      return;
    }
    setState(() {
      _busy = true;
      _data = null;
      _error = null;
      _selected = null;
    });
    final service = widget.service;
    final start = widget.start;
    final end = widget.end;
    final readGeneration = _generation;
    var continueReading = true;
    try {
      final generation = readGeneration;
      final data = await service
          .read(
            start,
            end,
            canRead: () =>
                continueReading &&
                mounted &&
                _foreground &&
                generation == _generation &&
                widget.isCurrentOwner(),
          )
          .timeout(const Duration(seconds: 20));
      if (mounted &&
          _foreground &&
          generation == _generation &&
          widget.isCurrentOwner()) {
        setState(() {
          _data = data;
          if (data.sources.isNotEmpty) _selected = data.sources.first.id;
        });
      }
    } catch (error) {
      if (mounted &&
          _foreground &&
          widget.isCurrentOwner() &&
          readGeneration == _generation) {
        setState(
          () => _error = error is HealthAccessException
              ? error.message
              : '건강 데이터를 읽지 못했습니다. 권한과 기기 잠금 상태를 확인해 주세요.',
        );
      }
    } finally {
      continueReading = false;
      if (mounted && readGeneration == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrentOwner()) return const SizedBox.shrink();
    final selected = _data?.sources
        .where((source) => source.id == _selected)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '심박·칼로리',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: '건강 데이터 새로고침',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh, size: 18),
            ),
            IconButton(
              tooltip: '건강 데이터 안내',
              icon: const Icon(Icons.info_outline, size: 18),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('건강 데이터 안내'),
                  content: Text(
                    '러닝 시작부터 종료까지의 자료이며 일시 정지 시간도 포함합니다. 평균 심박은 표본 평균, 칼로리는 기기 추정값입니다. 직접 입력·시간 밖 표본은 제외하며 비어 있는 값은 추정하지 않습니다. 아이폰은 읽기 거절과 자료 없음을 구분할 수 없습니다.'
                    '${_error == null ? '' : '\n\n$_error'}'
                    '${_data?.notices.isNotEmpty == true ? '\n\n${_data!.notices.join('\n')}' : ''}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('확인'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_data != null) ...[
          if (_data!.sources.length > 1)
            DropdownButton<String>(
              isExpanded: true,
              value: _selected,
              hint: const Text('기기 선택'),
              items: [
                for (var i = 0; i < _data!.sources.length; i++)
                  DropdownMenuItem(
                    value: _data!.sources[i].id,
                    child: Text(
                      '${i + 1}. ${_data!.sources[i].label}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _selected = value),
            ),
        ],
        ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricValue(
                  label: '평균 심박',
                  value: selected?.averageHeartRate == null
                      ? '--'
                      : '${selected!.averageHeartRate!.round()} 회/분',
                ),
              ),
              Expanded(
                child: MetricValue(
                  label: '최대 심박',
                  value: selected?.maxHeartRate == null
                      ? '--'
                      : '${selected!.maxHeartRate!.round()} 회/분',
                ),
              ),
              Expanded(
                child: MetricValue(
                  label: '활동 칼로리',
                  value: selected?.activeCalories == null
                      ? '--'
                      : '${selected!.activeCalories!.toStringAsFixed(0)} kcal',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (selected != null)
            Text(
              selected.label,
              style: const TextStyle(color: AppColors.gray, fontSize: 12),
            ),
          if (selected?.overlappingCalories == true)
            const Text('칼로리 자료 중복', style: TextStyle(color: AppColors.gray)),
        ],
      ],
    );
  }
}
