import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_feedback/data/run_feedback_service.dart';
import 'package:runquest/features/run_feedback/run_feedback_panel.dart';

class FakeFeedback implements RunFeedbackService {
  @override
  bool isCurrentOwner = true;
  RunFeedbackState state = const RunFeedbackState(
    status: FeedbackStatus.available,
  );
  int loads = 0;
  int generations = 0;
  bool fail = false;
  Completer<RunFeedbackState>? response;
  @override
  Future<RunFeedbackState> load(String runId) async {
    loads++;
    if (fail) throw Exception('연결 실패');
    return response == null ? state : response!.future;
  }

  @override
  Future<RunFeedbackState> generate(String runId) async {
    generations++;
    state = RunFeedbackState(
      status: FeedbackStatus.ready,
      message: '기록을 남기셨습니다. 이전 기록이 없어 비교하기 어렵습니다. 다음 기록과 함께 살펴보세요.',
      createdAt: DateTime.utc(2026, 10, 13),
    );
    return state;
  }
}

void main() {
  Future<void> show(WidgetTester tester, FakeFeedback service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RunFeedbackPanel(runId: 'run', service: service),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('화면을 열거나 새로고침해도 AI를 자동 호출하지 않습니다', (tester) async {
    final service = FakeFeedback();
    await show(tester, service);
    await tester.tap(find.byTooltip('피드백 상태 확인'));
    await tester.pumpAndSettle();
    expect(service.loads, 2);
    expect(service.generations, 0);
  });
  testWidgets('전송 안내 취소는 AI를 호출하지 않고 동의 후 한 번만 생성합니다', (tester) async {
    final service = FakeFeedback();
    await show(tester, service);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Google Gemini'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(service.generations, 0);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('동의하고 요청'));
    await tester.pumpAndSettle();
    expect(service.generations, 1);
    expect(find.text(service.state.message!), findsOneWidget);
    expect(find.text('AI 피드백 요청'), findsNothing);
    await tester.tap(find.byTooltip('피드백 상태 확인'));
    await tester.pumpAndSettle();
    expect(service.generations, 1);
  });
  testWidgets('72시간 제한 상태는 다음 시각과 함께 표시하고 기기 시계로 해제하지 않습니다', (tester) async {
    final service = FakeFeedback()
      ..state = RunFeedbackState(
        status: FeedbackStatus.cooldown,
        nextAvailableAt: DateTime.utc(2000),
      );
    await show(tester, service);
    expect(find.textContaining('다음 요청:'), findsOneWidget);
    expect(find.text('AI 피드백 요청'), findsNothing);
    expect(service.generations, 0);
  });
  testWidgets('연결 실패는 생성 버튼을 열지 않고 상태 조회로 복구합니다', (tester) async {
    final service = FakeFeedback()..fail = true;
    await show(tester, service);
    expect(find.text('AI 피드백 요청'), findsNothing);
    service.fail = false;
    await tester.tap(find.byTooltip('피드백 상태 확인'));
    await tester.pumpAndSettle();
    expect(find.text('AI 피드백 요청'), findsOneWidget);
  });
  testWidgets('계정 전환 뒤 이전 계정의 피드백을 표시하지 않습니다', (tester) async {
    final service = FakeFeedback()
      ..state = RunFeedbackState(
        status: FeedbackStatus.ready,
        message: '이전 계정 피드백',
        createdAt: DateTime.utc(2026),
      );
    await show(tester, service);
    service.isCurrentOwner = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunFeedbackPanel(runId: 'run', service: service),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('이전 계정 피드백'), findsNothing);
    expect(find.text('로그인 상태를 확인해 주세요.'), findsOneWidget);
  });
  testWidgets('좁은 화면에서도 긴 결과와 버튼이 넘치지 않습니다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeFeedback()
      ..state = RunFeedbackState(
        status: FeedbackStatus.ready,
        message: '러닝 기록을 확인해 보세요. ' * 25,
        createdAt: DateTime.utc(2026),
      );
    await show(tester, service);
    expect(tester.takeException(), isNull);
  });
  testWidgets('진행 중 결과는 조회만 반복하고 생성하지 않습니다', (tester) async {
    final service = FakeFeedback()
      ..state = RunFeedbackState(
        status: FeedbackStatus.processing,
        nextAvailableAt: DateTime.utc(2026, 10, 16),
      );
    await show(tester, service);
    service.state = RunFeedbackState(
      status: FeedbackStatus.ready,
      message: '저장된 피드백',
      createdAt: DateTime.utc(2026),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('저장된 피드백'), findsOneWidget);
    expect(service.generations, 0);
    await tester.pumpWidget(const SizedBox());
  });
  test('잘못된 서버 상태·제한 시각·피드백은 거부합니다', () {
    for (final json in [
      {'status': 'reserved'},
      {'status': 'cooldown'},
      {'status': 'ready', 'message': '위조'},
    ]) {
      expect(() => RunFeedbackState.fromJson(json), throwsFormatException);
    }
  });
}
