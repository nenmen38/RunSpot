import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/shared/widgets/footprint_loader.dart';

void main() {
  testWidgets('발자국은 달리듯 바뀌고 동작 줄이기를 켜면 멈춥니다', (tester) async {
    const key = ValueKey('발자국');
    Future<void> show({required bool still}) => tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(key: key, child: FootprintLoader()),
          ),
        ),
      ),
    );

    Future<Uint8List> pixels() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      return (await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List();
        } finally {
          image.dispose();
        }
      }))!;
    }

    await show(still: false);
    await tester.pump();
    final first = await pixels();
    final size = tester.getSize(find.byKey(key));
    expect(size, tester.view.physicalSize / tester.view.devicePixelRatio);
    bool hasPrintIn(Uint8List frame, Rect area) {
      for (var y = area.top.ceil(); y < area.bottom.floor(); y++) {
        for (var x = area.left.ceil(); x < area.right.floor(); x++) {
          if (frame[(y * size.width.toInt() + x) * 4 + 3] > 100) return true;
        }
      }
      return false;
    }

    final upperLeft = const Rect.fromLTWH(0, 0, 80, 80);
    final lowerRight = Rect.fromLTWH(size.width - 80, size.height - 80, 80, 80);
    expect(hasPrintIn(first, lowerRight), isTrue);
    expect(hasPrintIn(first, upperLeft), isFalse);
    await tester.pump(const Duration(milliseconds: 800));
    final last = await pixels();
    expect(hasPrintIn(last, upperLeft), isTrue);
    expect(hasPrintIn(last, lowerRight), isFalse);

    await show(still: true);
    final still = await pixels();
    expect(still.any((value) => value != 0), isTrue);
    await tester.pump(const Duration(milliseconds: 360));
    expect(await pixels(), orderedEquals(still));
    expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
  });
}
