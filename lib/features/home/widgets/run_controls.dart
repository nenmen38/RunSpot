import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/formatters/run_format.dart';
import '../../../shared/theme/app_colors.dart';
import '../live_map_controller.dart';

class RunControls extends StatelessWidget {
  const RunControls({
    required this.controller,
    required this.onFinish,
    this.busy = false,
    super.key,
  });

  final LiveMapController controller;
  final VoidCallback onFinish;
  final bool busy;

  /// 새 러닝을 시작하기 전 3·2·1을 세는 초입니다. 0이면 바로 시작합니다.
  static int countdownSeconds = 3;

  Future<void> _start(BuildContext context) async {
    if (countdownSeconds > 0) {
      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RunStartCountdown(seconds: countdownSeconds),
      );
      if (go != true || !context.mounted) return;
    }
    unawaited(HapticFeedback.heavyImpact());
    await controller.startRun();
  }

  @override
  Widget build(BuildContext context) {
    final session = controller.runSession;
    final running = session?.isRunning == true;
    final waiting =
        busy ||
        controller.startingRun ||
        controller.savingRun ||
        controller.groupPreparing ||
        controller.groupPrepared;
    final finished = session?.isFinished == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.groupPreparing || controller.groupPrepared)
          Row(
            children: [
              const Expanded(child: Text('그룹 출발 준비 중입니다. 앱을 열어 두세요.')),
              TextButton(
                onPressed: controller.cancelGroupPreparation,
                child: const Text('준비 취소'),
              ),
            ],
          ),
        if (session != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              finished
                  ? '저장 대기'
                  : running
                  ? '러닝 중'
                  : '일시 정지',
              style: TextStyle(
                color: running ? const Color(0xFF16836F) : Colors.grey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _RunMetric(
                  label: '거리',
                  value:
                      '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RunMetric(
                  label: '시간',
                  value: formatRunDuration(session.duration),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RunMetric(
                  label: '현재 페이스',
                  value: formatPaceDuration(session.currentPace),
                  unit: '/km',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RunMetric(
                  label: '평균 페이스',
                  value: formatPaceDuration(session.averagePace),
                  unit: '/km',
                ),
              ),
            ],
          ),
        ],
        if (controller.runError != null) ...[
          const SizedBox(height: 6),
          Text(controller.runError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: waiting || controller.locating || finished
                    ? null
                    : () {
                        if (running) {
                          unawaited(HapticFeedback.mediumImpact());
                          controller.pauseRun();
                        } else if (session == null) {
                          unawaited(_start(context));
                        } else {
                          // 일시 정지 뒤 다시 달릴 때는 세지 않고 바로 이어갑니다.
                          unawaited(HapticFeedback.heavyImpact());
                          controller.startRun();
                        }
                      },
                icon: waiting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(running ? Icons.pause : Icons.play_arrow),
                label: Text(
                  running
                      ? '일시 정지'
                      : session == null
                      ? '러닝 시작'
                      : '러닝 계속',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: session == null || waiting
                    ? null
                    : () {
                        unawaited(HapticFeedback.mediumImpact());
                        onFinish();
                      },
                icon: const Icon(Icons.stop),
                label: Text(finished ? '저장 재시도' : '러닝 종료'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RunMetric extends StatelessWidget {
  const _RunMetric({required this.label, required this.value, this.unit});
  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      SizedBox(
        height: 28,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              text: value,
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ],
  );
}

/// 러닝 시작 전 화면 가운데에 3·2·1을 보여줍니다. 다 세면 true, 취소하면 false를 돌려줍니다.
class RunStartCountdown extends StatefulWidget {
  const RunStartCountdown({this.seconds = 3, super.key});

  final int seconds;

  @override
  State<RunStartCountdown> createState() => _RunStartCountdownState();
}

class _RunStartCountdownState extends State<RunStartCountdown> {
  late int _left = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(HapticFeedback.selectionClick());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      unawaited(HapticFeedback.selectionClick());
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '곧 출발해요',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Semantics(
            liveRegion: true,
            label: '$_left초 뒤 러닝 시작',
            child: ExcludeSemantics(
              child: SizedBox(
                width: 144,
                height: 144,
                child: FittedBox(
                  child: Text(
                    '$_left',
                    style: const TextStyle(
                      fontSize: 112,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
        ],
      ),
    ),
  );
}
