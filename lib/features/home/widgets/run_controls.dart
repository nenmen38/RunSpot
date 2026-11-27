import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/l10n.dart';
import '../../../shared/formatters/run_format.dart';
import '../../../shared/theme/app_colors.dart';
import '../live_map_controller.dart';
import '../models/run_session.dart';

class RunControls extends StatefulWidget {
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

  /// 홈 화면 위젯의 '러닝 시작'처럼 밖에서 시작을 부탁하면 true가 됩니다.
  /// 시작 버튼이 화면에 있으면 같은 카운트다운으로 시작하고 다시 false로 돌립니다.
  static final startRequested = ValueNotifier<bool>(false);

  @override
  State<RunControls> createState() => _RunControlsState();
}

class _RunControlsState extends State<RunControls> {
  RunSession? _lockedSession;

  @override
  void initState() {
    super.initState();
    RunControls.startRequested.addListener(_startRequested);
    // 앱이 막 켜지면서 부탁받은 경우도 처리합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startRequested());
  }

  @override
  void dispose() {
    RunControls.startRequested.removeListener(_startRequested);
    super.dispose();
  }

  void _startRequested() {
    if (!mounted || !RunControls.startRequested.value) return;
    RunControls.startRequested.value = false;
    final controller = widget.controller;
    // 이미 달리는 중이거나 준비 중이면 그대로 둡니다.
    if (controller.runSession != null ||
        widget.busy ||
        controller.startingRun ||
        controller.savingRun ||
        controller.groupPreparing ||
        controller.groupPrepared) {
      return;
    }
    unawaited(_start(context));
  }

  Future<void> _start(BuildContext context) async {
    if (RunControls.countdownSeconds > 0) {
      final go = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            RunStartCountdown(seconds: RunControls.countdownSeconds),
      );
      if (go != true || !context.mounted) return;
    }
    unawaited(HapticFeedback.heavyImpact());
    await widget.controller.startRun();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final session = controller.runSession;
    final running = session?.isRunning == true;
    final locked = running && identical(session, _lockedSession);
    final waiting =
        widget.busy ||
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
              Expanded(child: Text(context.l10n.runGroupPreparing)),
              TextButton(
                onPressed: controller.cancelGroupPreparation,
                child: Text(context.l10n.runCancelPreparation),
              ),
            ],
          ),
        if (session != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              finished
                  ? context.l10n.runWaitingSave
                  : session.isAutoPaused
                  // 멈춰 있어 시간을 잠시 멈춘 상태입니다. 다시 달리면 바로 이어집니다.
                  ? context.l10n.runAutoPaused
                  : running
                  ? (locked
                        ? context.l10n.runRunningLocked
                        : context.l10n.runRunning)
                  : context.l10n.runPause,
              style: TextStyle(
                color: session.isAutoPaused
                    ? AppColors.orange
                    : running
                    ? (AppColors.dark
                          ? AppColors.green
                          : const Color(0xFF16836F))
                    : AppColors.gray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _RunMetric(
                  label: context.l10n.runDistance,
                  value:
                      '${(session.distanceMeters / 1000).toStringAsFixed(2)} km',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RunMetric(
                  label: context.l10n.runTime,
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
                  label: context.l10n.runCurrentPace,
                  value: formatPaceDuration(session.currentPace),
                  unit: '/km',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RunMetric(
                  label: context.l10n.runAveragePace,
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
        if (locked)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: null,
            onLongPress: () {
              unawaited(HapticFeedback.selectionClick());
              setState(() => _lockedSession = null);
            },
            icon: const Icon(Icons.lock),
            label: Text(context.l10n.runHoldToUnlock),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final primary = FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: waiting || controller.locating || finished
                    ? null
                    : () {
                        if (running) {
                          unawaited(HapticFeedback.mediumImpact());
                          _lockedSession = null;
                          controller.pauseRun();
                        } else if (session == null) {
                          unawaited(_start(context));
                        } else {
                          // 일시 정지 뒤 다시 달릴 때는 세지 않고 바로 이어갑니다.
                          unawaited(HapticFeedback.heavyImpact());
                          _lockedSession = null;
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
                      ? context.l10n.runPause
                      : session == null
                      ? context.l10n.runStart
                      : context.l10n.runResume,
                ),
              );
              if (session == null) return primary;
              final finish = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: waiting
                    ? null
                    : () {
                        unawaited(HapticFeedback.mediumImpact());
                        widget.onFinish();
                      },
                icon: const Icon(Icons.stop),
                label: Text(
                  finished ? context.l10n.runRetrySave : context.l10n.runFinish,
                ),
              );
              final stack =
                  MediaQuery.textScalerOf(context).scale(14) * 17 >
                  constraints.maxWidth;
              final showLockLabel = stack || constraints.maxWidth >= 350;
              final lock = Tooltip(
                message: context.l10n.runLockTooltip,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: showLockLabel
                        ? const EdgeInsets.symmetric(horizontal: 10)
                        : EdgeInsets.zero,
                    foregroundColor: AppColors.blueText,
                  ),
                  onPressed: waiting
                      ? null
                      : () {
                          unawaited(HapticFeedback.selectionClick());
                          setState(() => _lockedSession = session);
                        },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 20),
                      if (showLockLabel) ...[
                        const SizedBox(width: 4),
                        Text(context.l10n.runLock),
                      ],
                    ],
                  ),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stack) ...[primary, const SizedBox(height: 8)],
                  Row(
                    children: [
                      if (!stack) ...[
                        Expanded(child: primary),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: finish),
                      if (running) ...[const SizedBox(width: 8), lock],
                    ],
                  ),
                ],
              );
            },
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
      Text(label, style: TextStyle(fontSize: 12, color: AppColors.gray)),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
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
          Text(
            context.l10n.countdownTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          Semantics(
            liveRegion: true,
            label: context.l10n.countdownLabel(_left),
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
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    ),
  );
}
