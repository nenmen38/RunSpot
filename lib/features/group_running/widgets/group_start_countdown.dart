import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../group_controller.dart';

/// 서버 공동 출발 시각을 기준으로 홈 중앙에 남은 초를 표시합니다.
class GroupStartCountdown extends StatelessWidget {
  const GroupStartCountdown({required this.controller, super.key});
  final GroupController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final group = controller.countdownGroup;
      if (group == null) return const SizedBox.shrink();
      final seconds = controller.secondsUntil(group)!.clamp(1, 10);
      return IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.3),
          child: Center(
            child: Semantics(
              liveRegion: true,
              label: '함께 달리기 $seconds초 뒤 출발',
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '함께 달리기',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(
                        width: 144,
                        height: 144,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Text(
                            '$seconds',
                            style: const TextStyle(
                              fontSize: 112,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                              color: AppColors.blue,
                            ),
                          ),
                        ),
                      ),
                      const Text('잠시 후 출발', style: TextStyle(fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
