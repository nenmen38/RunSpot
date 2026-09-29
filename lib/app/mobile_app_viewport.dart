import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class MobileAppViewport extends StatelessWidget {
  const MobileAppViewport({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
