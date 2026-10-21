import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/profile/widgets/run_sharing_control.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';

import 'support/live_map_fakes.dart';
import 'support/run_history_fakes.dart';
import 'support/run_sharing_preference_fake.dart';

void main() {
  late FakeLocationService location;
  late FakeRunSharingPreferenceService preference;
  late RunHistoryController history;
  late LiveMapController controller;

  setUp(() async {
    location = FakeLocationService();
    preference = FakeRunSharingPreferenceService();
    history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
      sharingPreferenceService: preference,
    );
    await controller.loadSharingPreference();
  });

  tearDown(() async {
    controller.dispose();
    history.dispose();
    await location.updates.close();
  });

  Future<void> showControl(WidgetTester tester, {String? problem}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RunSharingControl(
            controller: controller,
            enablingProblem: problem,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.tap(find.text('러닝 중 위치 공유'));
    await tester.pumpAndSettle();
  }

  testWidgets('평소에는 설정명과 상태만 표시하고 취소하면 저장하지 않습니다', (tester) async {
    await showControl(tester);
    expect(find.text('끔'), findsOneWidget);
    expect(find.textContaining('러닝 시작·재개'), findsNothing);
    await toggle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(preference.saves, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(controller.shareWhileRunning, isFalse);
    expect(preference.saves, isEmpty);
  });

  testWidgets('안내에 동의하면 켜지고 끌 때는 확인창 없이 즉시 꺼집니다', (tester) async {
    await showControl(tester);
    await toggle(tester);
    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();
    expect(find.text('켬'), findsOneWidget);
    expect(preference.saves, [true]);
    await toggle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('끔'), findsOneWidget);
    expect(preference.saves, [true, false]);
  });

  testWidgets('저장된 켜짐 설정을 표시할 때는 확인창을 반복하지 않습니다', (tester) async {
    preference.enabled = true;
    await controller.loadSharingPreference();
    await showControl(tester);
    expect(find.text('켬'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(preference.saves, isEmpty);
  });

  testWidgets('인증·공개 조건 안내는 켜기를 시도할 때만 표시합니다', (tester) async {
    const problem = '이메일 인증 후 위치 공유를 켤 수 있습니다.';
    await showControl(tester, problem: problem);
    expect(find.text(problem), findsNothing);
    await toggle(tester);
    expect(find.text(problem), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(preference.saves, isEmpty);
    await showControl(tester);
    expect(find.text(problem), findsNothing);
    await toggle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
  });

  testWidgets('확인창이 열린 동안 공개 조건이 바뀌면 공유를 켜지 않습니다', (tester) async {
    await showControl(tester);
    await toggle(tester);
    const problem = '친구 또는 전체 공개로 설정한 뒤 위치 공유를 켜 주세요.';
    await showControl(tester, problem: problem);
    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();
    expect(find.text(problem), findsOneWidget);
    expect(controller.shareWhileRunning, isFalse);
    expect(preference.saves, isEmpty);
  });

  testWidgets('저장 실패 안내와 재시도를 유지합니다', (tester) async {
    preference.saveFailure = StateError('저장 실패');
    await showControl(tester);
    await toggle(tester);
    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();
    expect(controller.shareWhileRunning, isFalse);
    expect(find.text(controller.sharingPreferenceError!), findsOneWidget);
    preference.saveFailure = null;
    await tester.tap(find.text('설정 다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('켬'), findsOneWidget);
    expect(controller.sharingPreferenceError, isNull);
  });
}
