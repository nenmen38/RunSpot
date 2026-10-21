import 'package:flutter/material.dart';

import '../../home/live_map_controller.dart';

class RunSharingControl extends StatefulWidget {
  const RunSharingControl({
    required this.controller,
    required this.enablingProblem,
    super.key,
  });
  final LiveMapController controller;
  final String? enablingProblem;

  @override
  State<RunSharingControl> createState() => _RunSharingControlState();
}

class _RunSharingControlState extends State<RunSharingControl> {
  bool _attemptedEnable = false;
  bool _confirming = false;

  Future<void> _change(bool enabled) async {
    final controller = widget.controller;
    if (!enabled) {
      setState(() => _attemptedEnable = false);
      await controller.setShareWhileRunning(false);
      return;
    }
    setState(() => _attemptedEnable = true);
    if (widget.enablingProblem != null || _confirming) return;
    setState(() => _confirming = true);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('러닝 중 위치를 공유할까요?'),
        content: const Text(
          '러닝 시작·재개 시 설정한 공개 범위에 따라 위치를 공유합니다. '
          '일시 정지·종료 시 공유를 중단합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('켜기'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (accepted != true ||
        controller != widget.controller ||
        widget.enablingProblem != null) {
      return;
    }
    await controller.setShareWhileRunning(true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('러닝 중 위치 공유'),
              subtitle: Text(controller.shareWhileRunning ? '켬' : '끔'),
              value: controller.shareWhileRunning,
              onChanged:
                  _confirming ||
                      controller.loadingSharingPreference ||
                      controller.savingSharingPreference ||
                      !controller.sharingPreferenceLoaded
                  ? null
                  : _change,
            ),
          ),
          if (_attemptedEnable && widget.enablingProblem != null)
            Text(
              widget.enablingProblem!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (controller.loadingSharingPreference ||
              controller.savingSharingPreference)
            const LinearProgressIndicator(),
          if (controller.sharingPreferenceError != null) ...[
            Text(
              controller.sharingPreferenceError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed:
                  controller.loadingSharingPreference ||
                      controller.savingSharingPreference
                  ? null
                  : controller.retrySharingPreference,
              child: const Text('설정 다시 시도'),
            ),
          ],
        ],
      ),
    );
  }
}
