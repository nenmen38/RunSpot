import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
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

  @override
  Widget build(BuildContext context) {
    final session = controller.runSession;
    final running = session?.isRunning == true;
    final waiting = busy || controller.startingRun || controller.savingRun;
    final finished = session?.isFinished == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                          controller.pauseRun();
                        } else {
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
                onPressed: session == null || waiting ? null : onFinish,
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
