import 'package:flutter/material.dart';

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
    final waiting = busy || controller.startingRun;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _RunMetric(
                  label: '거리',
                  value:
                      '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',
                ),
              ),
              Expanded(
                child: _RunMetric(
                  label: '시간',
                  value: formatRunDuration(session.duration),
                ),
              ),
              Text(
                running ? '러닝 중' : '일시 정지',
                style: TextStyle(
                  color: running ? const Color(0xFF16836F) : Colors.grey,
                  fontWeight: FontWeight.w700,
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
                onPressed: waiting || controller.locating
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
                label: const Text('러닝 종료'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RunMetric extends StatelessWidget {
  const _RunMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

String formatRunDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
