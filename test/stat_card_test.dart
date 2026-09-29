import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/shared/widgets/stat_card.dart';

void main() {
  for (final bounded in [true, false]) {
    testWidgets('통계 카드 높이 제한 여부: $bounded', (tester) async {
      const card = StatCard(label: '이번 주', value: '31.4km', icon: Icons.route);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: bounded
                ? const SizedBox(width: 120, height: 180, child: card)
                : const Column(children: [SizedBox(width: 120, child: card)]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('31.4km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
