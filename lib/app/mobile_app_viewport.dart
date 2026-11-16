import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

/// 웹 미리보기에서만 앱을 폰 모양 틀 안에 보여줍니다.
/// 실제 휴대폰·태블릿·폴더블에서는 기기 화면 크기 그대로 배치해 잘리거나 늘어나지 않게 합니다.
class MobileAppViewport extends StatelessWidget {
  const MobileAppViewport({
    required this.child,
    this.framed = kIsWeb,
    super.key,
  });

  final Widget child;

  /// 폰 모양 틀을 씌울지 여부입니다. 기본값은 웹에서만 true입니다.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    if (!framed) return child;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const phoneAspectRatio = 390 / 844;
            final maxWidth = math.min(constraints.maxWidth, 430.0);
            final maxHeight = math.min(constraints.maxHeight, 932.0);
            var width = maxWidth;
            var height = width / phoneAspectRatio;
            if (height > maxHeight) {
              height = maxHeight;
              width = height * phoneAspectRatio;
            }
            return Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: constraints.maxWidth > 430
                    ? BorderRadius.circular(32)
                    : BorderRadius.zero,
                boxShadow: constraints.maxWidth > 430
                    ? [
                        BoxShadow(
                          color: AppColors.ink.withValues(alpha: .10),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(width: 390, height: 844, child: child),
              ),
            );
          },
        ),
      ),
    );
  }
}
