import 'package:flutter/material.dart';

import '../../home/live_map_controller.dart';

class RunSharingControl extends StatelessWidget {
  const RunSharingControl({required this.controller, super.key});
  final LiveMapController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('러닝 시 위치 공유'),
            subtitle: const Text(
              '러닝 시작·재개 시 자동 공유하며 일시 정지·종료 시 중단합니다.\n이메일 인증과 친구 또는 전체 공개 설정이 필요합니다.',
            ),
            value: controller.shareWhileRunning,
            onChanged:
                controller.loadingSharingPreference ||
                    controller.savingSharingPreference ||
                    !controller.sharingPreferenceLoaded
                ? null
                : controller.setShareWhileRunning,
          ),
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
