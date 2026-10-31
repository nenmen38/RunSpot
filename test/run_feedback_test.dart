import 'package:runquest/features/run_feedback/models/run_feedback_context.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/run_feedback/data/run_feedback_service.dart';
import 'package:runquest/features/run_feedback/run_feedback_panel.dart';
import 'package:runquest/features/run_feedback/models/run_feedback_heart_summary.dart';
import 'package:runquest/features/health/models/run_health_data.dart';

class FakeFeedback implements RunFeedbackService {
  @override
  bool isCurrentOwner = true;
  RunFeedbackState state = const RunFeedbackState(
    status: FeedbackStatus.available,
  );
  int loads = 0;
  int generations = 0;
  RunFeedbackHeartSummary? sentHeart;
  bool fail = false;
  Completer<RunFeedbackState>? response;
  @override
  Future<RunFeedbackState> load(String runId) async {
    loads++;
    if (fail) throw Exception('연결 실패');
    return response == null ? state : response!.future;
  }

  @override
  Future<RunFeedbackContext?> loadContext(String runId) async => null;

  @override
  Future<RunFeedbackState> generate(
    String runId, {
    RunFeedbackHeartSummary? heartSummary,
  }) async {
    generations++;
    sentHeart = heartSummary;
    state = RunFeedbackState(
      status: FeedbackStatus.ready,
      message: '기록을 남기셨습니다. 이전 기록이 없어 비교하기 어렵습니다. 다음 기록과 함께 살펴보세요.',
      createdAt: DateTime.utc(2026, 10, 13),
    );
    return state;
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    FakeFeedback service, {
    RunHealthSource? Function()? readHeartSource,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RunFeedbackPanel(
                runId: 'run',
                service: service,
                readHeartSource: readHeartSource,
              ),
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
    expect(find.text('피드백을 생성할까요?'), findsOneWidget);
    expect(find.text('데이터 이용 안내'), findsNothing);
    expect(find.textContaining('Google Gemini'), findsNothing);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(service.generations, 0);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('생성하기'));
    await tester.pumpAndSettle();
    expect(service.generations, 1);
    expect(find.text(service.state.message!), findsOneWidget);
    expect(find.text('AI 피드백 요청'), findsNothing);
    await tester.tap(find.byTooltip('피드백 상태 확인'));
    await tester.pumpAndSettle();
    expect(service.generations, 1);
  });
  const heartSource = RunHealthSource(
    id: 'private-device',
    label: '내 워치',
    heartSamples: 30,
    averageHeartRate: 145.4,
    maxHeartRate: 170,
  );
  testWidgets('심박 전송은 기본 해제되며 동의하지 않으면 보내지 않습니다', (tester) async {
    final service = FakeFeedback();
    await show(tester, service, readHeartSource: () => heartSource);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    await tester.tap(find.text('생성하기'));
    await tester.pumpAndSettle();
    expect(service.generations, 1);
    expect(service.sentHeart, isNull);
  });
  testWidgets('심박 전송을 선택한 요청에만 선택 기기의 숫자 요약을 보냅니다', (tester) async {
    final service = FakeFeedback();
    await show(tester, service, readHeartSource: () => heartSource);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('생성하기'));
    await tester.pumpAndSettle();
    expect(service.sentHeart?.toJson(), {
      'average_bpm': 145,
      'max_bpm': 170,
      'sample_count': 30,
    });
  });
  testWidgets('동의 중 심박 자료가 바뀌면 오래된 자료를 보내지 않습니다', (tester) async {
    final service = FakeFeedback();
    RunHealthSource? source = heartSource;
    await show(tester, service, readHeartSource: () => source);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    source = null;
    await tester.tap(find.text('생성하기'));
    await tester.pumpAndSettle();
    expect(service.generations, 0);
    expect(find.textContaining('심박 자료가 변경'), findsOneWidget);
  });
  testWidgets('동의 중 백그라운드로 이동하면 새 요청을 보내지 않습니다', (tester) async {
    final service = FakeFeedback();
    await show(tester, service, readHeartSource: () => heartSource);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('생성하기'));
    await tester.pumpAndSettle();
    expect(service.generations, 0);
  });
  testWidgets('좁은 화면에서도 심박 동의 내용을 스크롤하고 취소 후 선택을 초기화합니다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = FakeFeedback();
    await show(tester, service, readHeartSource: () => heartSource);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(service.generations, 0);
    await tester.tap(find.text('AI 피드백 요청'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
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
