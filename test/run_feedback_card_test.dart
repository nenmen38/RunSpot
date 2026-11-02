import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_feedback/data/run_feedback_service.dart';
import 'package:runquest/features/run_feedback/widgets/run_feedback_card.dart';
import 'package:runquest/features/run_history/models/run_record.dart';

void main() {
  final record = RunRecord(
    id: 'run',
    clientRunId: 'client',
    startedAt: DateTime.utc(2026, 11, 2),
    endedAt: DateTime.utc(2026, 11, 2, 0, 30),
    distanceMeters: 5000,
    durationSeconds: 1800,
  );
  const message =
      '이번 러닝의 평균 페이스는 6분이야. 이전 기록이 없어 변화는 비교하기 어려워. 다음 러닝도 같은 구간을 달리고 페이스를 비교해 봐.';
  for (final width in [320.0, 390.0, 900.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('분석 카드는 너비 $width·글자 배율 $scale에서 실제 기록과 전체 피드백을 표시합니다', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: RunFeedbackCard(
                      state: RunFeedbackState(
                        status: FeedbackStatus.ready,
                        message: message,
                        createdAt: record.endedAt,
                      ),
                      description: message,
                      busy: false,
                      onRefresh: () {},
                      record: record,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('러닝 피드백'), findsOneWidget);
        expect(find.text('AI 분석 완료'), findsOneWidget);
        for (final sentence in [
          '이번 러닝의 평균 페이스는 6분이야.',
          '이전 기록이 없어 변화는 비교하기 어려워.',
          '다음 러닝도 같은 구간을 달리고 페이스를 비교해 봐.',
        ]) {
          expect(find.text(sentence), findsOneWidget);
        }
        expect(find.text('5.00 km'), findsOneWidget);
        expect(find.text('30:00'), findsOneWidget);
        expect(find.text('6:00 /km'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('기록을 전달하지 않으면 측정값을 임의로 표시하지 않습니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunFeedbackCard(
            state: RunFeedbackState(
              status: FeedbackStatus.ready,
              message: message,
              createdAt: record.endedAt,
            ),
            description: message,
            busy: false,
            onRefresh: () {},
          ),
        ),
      ),
    );
    expect(find.text('분석 대상 기록'), findsNothing);
    expect(find.text('5.00 km'), findsNothing);
    for (final sentence in [
      '이번 러닝의 평균 페이스는 6분이야.',
      '이전 기록이 없어 변화는 비교하기 어려워.',
      '다음 러닝도 같은 구간을 달리고 페이스를 비교해 봐.',
    ]) {
      expect(find.text(sentence), findsOneWidget);
    }
  });
}
