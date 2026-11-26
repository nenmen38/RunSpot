import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/shared/maps/run_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// 기기 환경설정을 메모리에서 재현합니다.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:runquest/app/mobile_app_viewport.dart';
import 'package:runquest/features/onboarding/app_tour.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';
import 'package:runquest/app/run_quest_app.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/app/run_quest_shell.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/widgets/run_controls.dart';
import 'package:runquest/features/profile/widgets/run_sharing_control.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_share/run_share_screen.dart';
import 'package:runquest/features/run_conditions/conditions_controller.dart';

import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';
import 'support/friend_fakes.dart';
import 'support/conditions_fakes.dart';
import 'support/progress_fakes.dart';
import 'support/statistics_fakes.dart';

import 'package:runquest/features/progress/models/run_progress.dart';

class ServerIdRecordService extends FakeRunRecordService {
  @override
  Future<RunRecord> save(RunSummary summary) async {
    final saved = await super.save(summary);
    final record = RunRecord(
      id: 'server-record-id',
      clientRunId: saved.clientRunId,
      startedAt: saved.startedAt,
      endedAt: saved.endedAt,
      distanceMeters: saved.distanceMeters,
      durationSeconds: saved.durationSeconds,
      temperature: saved.temperature,
    );
    records[records.indexOf(saved)] = record;
    routes[record.id] = routes.remove(saved.id)!;
    return record;
  }
}

class MemoryAuthStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

Future<void> openPrivacySettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('계정·공개 설정'));
  await tester.pumpAndSettle();
}

void restoreRecordableRun(LiveMapController controller, {RunRoute? route}) {
  final now = DateTime.now().toUtc();
  controller.runSession = RunSession.restore(
    RunSummary(
      clientRunId: 'recordable-widget-run',
      startedAt: now.subtract(const Duration(minutes: 5)),
      endedAt: now,
      distanceMeters: 300,
      duration: const Duration(minutes: 5),
      route: route ?? const RunRoute.empty(),
    ),
  );
}

void main() {
  // 이 파일의 테스트는 시작 버튼을 누르면 바로 측정을 확인하므로 3초 카운트다운을 끕니다.
  setUpAll(() => RunControls.countdownSeconds = 0);
  var sharingEligible = false;
  setUp(() {
    sharingEligible = false;
    final previousPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(
      () => SharedPreferencesAsyncPlatform.instance = previousPreferences,
    );
  });
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-public-key',
      debug: false,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
        pkceAsyncStorage: MemoryAuthStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          request.url.path.endsWith('/my_email_verified')
              ? jsonEncode(sharingEligible)
              : jsonEncode({
                  'visibility': sharingEligible ? 'friends' : 'private',
                  'nickname': sharingEligible ? '러너' : null,
                }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'test-user-session',
        'refresh_token': 'test-refresh-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
        'user': {
          'id': '00000000-0000-0000-0000-000000000001',
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-10-09T00:00:00Z',
        },
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<LiveMapController> showApp(
    WidgetTester tester,
    Size size, {
    FakeRunRecordService? recordService,
    FakeProgressService? progressService,
    FakeStatisticsService? statisticsService,
    bool dark = false,
    AppTour? tour,
  }) async {
    AppColors.dark = dark;
    addTearDown(() => AppColors.dark = false);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final location = FakeLocationService();
    addTearDown(location.updates.close);
    final controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: RunHistoryController(
        recordService ?? FakeRunRecordService(),
        outbox: FakeRunOutbox(),
      ),
    );
    final conditions = ConditionsController(FakeConditionsService());
    addTearDown(conditions.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(dark: dark),
        home: MobileAppViewport(
          child: RunQuestShell(
            mapController: controller,
            tour: tour,
            mapBridgeFactory: FakeMapBridge.new,
            friendService: FakeFriendService(),
            conditionsController: conditions,
            progressService: progressService,
            statisticsService: statisticsService,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('홈 화면 위젯의 러닝 시작을 누르면 홈에서 바로 러닝을 시작합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    expect(controller.runSession, isNull);
    RunControls.startRequested.value = true;
    await tester.pump();
    await tester.pump();
    expect(RunControls.startRequested.value, isFalse);
    expect(controller.runSession, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('처음 실행하면 메뉴를 하나씩 직접 눌러 보는 둘러보기를 한 번만 보여줍니다', (tester) async {
    final saved = <String, String>{};
    final tour = AppTour(store: _TourStore(saved));
    await tour.load();
    expect(tour.showing, isTrue);
    await showApp(tester, const Size(390, 844), tour: tour);
    expect(find.text('뜀터에 오신 걸 환영해요'), findsOneWidget);
    // 메뉴를 비추는 동안에는 고리가 계속 퍼지므로 정해진 시간만큼만 넘깁니다.
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    await tester.tap(find.byKey(const ValueKey('tour-next')));
    await settle();

    // 메뉴마다: 밝게 뚫린 메뉴를 눌러 그 탭으로 옮겨 간 뒤 설명을 보고 다음으로 넘어갑니다.
    for (final (title, tab) in [
      ('홈 · 러닝 지도', '홈'),
      ('소셜 · 친구와 크루', '소셜'),
      ('프로필 · 내 기록', '프로필'),
      ('게시판 · 러닝 소식', '게시판'),
      ('아이템 · 꾸미기', '아이템'),
    ]) {
      expect(find.text(title), findsOneWidget);
      final target = find.byKey(const ValueKey('tour-target'));
      expect(target, findsOneWidget);
      // 뚫린 자리가 실제 하단 메뉴 위에 있습니다.
      final menu = tester.getCenter(find.text(tab).last);
      expect(tester.getRect(target).contains(menu), isTrue);
      await tester.tap(target);
      await settle();
      expect(find.byKey(const ValueKey('tour-target')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tour-next')));
      await settle();
    }
    expect(find.text('이제 달려 볼까요?'), findsOneWidget);
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(find.text('이제 달려 볼까요?'), findsNothing);
    expect(saved['onboarding.tour.v1'], 'done');

    // 다음 실행에서는 띄우지 않습니다.
    final again = AppTour(store: _TourStore(saved));
    await again.load();
    expect(again.showing, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('둘러보기는 건너뛸 수 있고 건너뛰어도 다시 띄우지 않습니다', (tester) async {
    final saved = <String, String>{};
    final tour = AppTour(store: _TourStore(saved));
    await tour.load();
    await showApp(tester, const Size(390, 844), tour: tour);
    await tester.tap(find.byKey(const ValueKey('tour-skip')));
    await tester.pumpAndSettle();
    expect(find.text('뜀터에 오신 걸 환영해요'), findsNothing);
    expect(saved['onboarding.tour.v1'], 'done');
    // 설정의 '다시 보기'로 처음부터 볼 수 있습니다.
    tour.restart();
    await tester.pumpAndSettle();
    expect(find.text('뜀터에 오신 걸 환영해요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('홈은 현재 위치 지도이며 코스 만들기 탭이 없습니다', (tester) async {
    await showApp(tester, const Size(390, 844));
    expect(find.byType(RunMap), findsOneWidget);
    expect(find.text('러닝 종료'), findsNothing);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, '러닝 시작')).width,
      greaterThan(300),
    );
    expect(
      tester.widget<RunMap>(find.byType(RunMap)).controller.camera.zoom,
      15.5,
    );
    expect(find.text('RunSpot'), findsNothing);
    expect(find.byTooltip('주변 러너 조회 반경'), findsNothing);
    expect(find.byTooltip('내 기록'), findsNothing);
    expect(find.byTooltip('프로필 및 공개 설정'), findsNothing);
    expect(find.bySemanticsLabel('내 현재 위치'), findsOneWidget);
    expect(find.text('주변 러너'), findsOneWidget);
    expect(find.text('양호'), findsOneWidget);
    expect(find.text('러닝 시작'), findsOneWidget);
    expect(find.text('코스'), findsNothing);
    expect(find.text('코스 만들기'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('홈에서 시작과 일시 정지 후 종료 결과를 확인합니다', (tester) async {
    final controller = await showApp(tester, const Size(320, 568));
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(controller.runSession!.isRunning, isTrue);
    final map = tester.widget<RunMap>(find.byType(RunMap)).controller;
    expect(map.camera.zoom, 16.5);
    expect(map.command['animate'], isTrue);
    expect(find.text('러닝 중'), findsOneWidget);
    expect(find.text('거리'), findsOneWidget);
    expect(find.text('현재 페이스'), findsOneWidget);
    expect(find.text('평균 페이스'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final lockButton = find.byTooltip('조작 잠금');
    final pauseButton = find.widgetWithText(FilledButton, '일시 정지');
    final finishButton = find.widgetWithText(OutlinedButton, '러닝 종료');
    await tester.ensureVisible(lockButton);
    expect(tester.getCenter(lockButton).dy, tester.getCenter(pauseButton).dy);
    expect(
      tester.getCenter(lockButton).dx,
      greaterThan(tester.getCenter(finishButton).dx),
    );
    await tester.tap(lockButton);
    await tester.pump();
    expect(pauseButton, findsNothing);
    expect(finishButton, findsNothing);
    expect(find.text('러닝 중 · 조작 잠김'), findsOneWidget);
    final unlockButton = find.text('길게 눌러 해제');
    await tester.ensureVisible(unlockButton);
    await tester.tap(unlockButton);
    await tester.pump();
    expect(unlockButton, findsOneWidget);
    expect(controller.runSession!.isRunning, isTrue);
    await tester.longPress(unlockButton);
    await tester.pump();
    await tester.ensureVisible(pauseButton);
    await tester.tap(find.text('일시 정지').last);
    await tester.pump();
    expect(controller.runSession!.isRunning, isFalse);
    expect(map.camera.zoom, 16.5);
    await tester.tap(find.text('러닝 계속'));
    await tester.pump();
    expect(controller.runSession!.isRunning, isTrue);
    await tester.tap(find.text('러닝 종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(controller.runSession!.isRunning, isTrue);
    restoreRecordableRun(controller);
    await tester.tap(find.text('러닝 종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('러닝 완료'), findsOneWidget);
    expect(controller.runSession, isNull);
    expect(map.camera.zoom, 15.5);
    expect(map.command['animate'], isFalse);
    expect(controller.runHistory.records, hasLength(1));
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('러닝 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('프로필').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('내 기록'));
    await tester.pumpAndSettle();
    expect(find.text('내 기록'), findsOneWidget);
    expect(find.text('0.30 km'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('최근 러닝'), findsOneWidget);
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(find.byType(RunMap), findsOneWidget);
    expect(find.text('내 기록'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('러닝 지도는 위치를 따라가되 수동 배율과 탐색을 존중합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    final location = controller.locationService as FakeLocationService;
    final map = tester.widget<RunMap>(find.byType(RunMap)).controller;
    await tester.drag(find.byType(RunMap), const Offset(90, 0));
    await tester.pump();
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(map.camera.zoom, 16.5);
    expect(map.camera.center.latitude, controller.position!.latitude);
    map.move(map.camera.center, 18);
    final origin = controller.position!.recordedAt;
    location.updates.add(
      testFix(
        latitude: 37.567,
        recordedAt: origin.add(const Duration(seconds: 5)),
      ),
    );
    await tester.pump();
    expect(map.camera.zoom, 18);
    expect(map.camera.center.latitude, 37.567);
    await tester.drag(find.byType(RunMap), const Offset(90, 0));
    await tester.pump();
    final explored = map.camera.center;
    location.updates.add(
      testFix(
        latitude: 37.568,
        recordedAt: origin.add(const Duration(seconds: 10)),
      ),
    );
    await tester.pump();
    expect(map.camera.center, explored);
    await tester.tap(find.byTooltip('내 위치로 이동'));
    await tester.pump();
    expect(map.camera.zoom, 16.5);
    expect(map.camera.center.latitude, 37.568);
    location.updates.add(
      testFix(
        latitude: 37.569,
        recordedAt: origin.add(const Duration(seconds: 15)),
      ),
    );
    await tester.pump();
    expect(map.camera.center.latitude, 37.569);
    expect(map.camera.zoom, 16.5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('미인증 프로필에서는 켜기를 누른 경우에만 인증 안내를 표시합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    await tester.tap(find.text('프로필').last);
    await tester.pumpAndSettle();
    await openPrivacySettings(tester);
    const problem = '이메일 인증 후 위치 공유를 켤 수 있습니다.';
    expect(
      tester
          .widget<RunSharingControl>(find.byType(RunSharingControl))
          .enablingProblem,
      problem,
    );
    expect(find.text(problem), findsNothing);
    await tester.ensureVisible(find.text('러닝 중 위치 공유'));
    await tester.tap(find.text('러닝 중 위치 공유'));
    await tester.pumpAndSettle();
    expect(find.text(problem), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.shareWhileRunning, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('프로필 공유 설정으로 러닝 중에만 자동 공유하고 끄면 즉시 중단합니다', (tester) async {
    sharingEligible = true;
    final controller = await showApp(tester, const Size(390, 844));
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.text('프로필').last);
    await tester.pumpAndSettle();
    await openPrivacySettings(tester);
    expect(find.text('공개 설정을 불러오지 못했습니다.'), findsNothing);
    expect(
      tester
          .widget<RunSharingControl>(find.byType(RunSharingControl))
          .enablingProblem,
      isNull,
    );
    await tester.ensureVisible(find.text('러닝 중 위치 공유'));
    await tester.tap(find.text('러닝 중 위치 공유'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();
    expect(controller.shareWhileRunning, isTrue);
    expect(controller.sharing, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('홈').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('러닝 시작'));
    await tester.pumpAndSettle();
    expect(controller.sharing, isTrue);
    await tester.tap(find.text('일시 정지'));
    await tester.pumpAndSettle();
    expect(controller.sharing, isFalse);
    await tester.tap(find.text('러닝 계속'));
    await tester.pumpAndSettle();
    expect(controller.sharing, isTrue);
    await tester.tap(find.text('프로필').last);
    await tester.pumpAndSettle();
    await openPrivacySettings(tester);
    await tester.ensureVisible(find.text('러닝 중 위치 공유'));
    await tester.tap(find.text('러닝 중 위치 공유'));
    await tester.pumpAndSettle();
    expect(controller.sharing, isFalse);
    expect(controller.shareWhileRunning, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('다른 탭을 다녀와도 지도와 공유 상태를 유지합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    await controller.setShareWhileRunning(true);
    await tester.tap(find.text('러닝 시작'));
    await tester.pumpAndSettle();
    expect(controller.sharing, isTrue);
    await tester.tap(find.text('소셜').last);
    await tester.pumpAndSettle();
    expect(find.text('내 친구 0'), findsOneWidget);
    await tester.tap(find.text('랭킹'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('랭킹 대상 선택'), findsOneWidget);
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    expect(controller.sharing, isTrue);
    expect(find.byType(RunMap), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('지도 경로와 페이스를 표시하고 일시 정지 구간을 연결하지 않습니다', (tester) async {
    final controller = await showApp(tester, const Size(320, 568));
    final location = controller.locationService as FakeLocationService;
    location.fix = testFix(
      recordedAt: DateTime.now().subtract(const Duration(seconds: 16)),
    );
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    final origin = controller.position!.recordedAt;
    location.updates.add(
      testFix(
        latitude: 37.567,
        recordedAt: origin.add(const Duration(seconds: 10)),
      ),
    );
    await tester.pump();
    expect(controller.runSession!.currentPace, isNotNull);
    final layerFinder = find.byType(RunMap);
    var layer = tester.widget<RunMap>(layerFinder);
    expect(layer.segments.single, hasLength(2));
    await tester.tap(find.text('일시 정지').last);
    await tester.pump();
    location.fix = testFix(
      latitude: 37.57,
      recordedAt: origin.add(const Duration(seconds: 11)),
    );
    await tester.tap(find.text('러닝 계속'));
    await tester.pump();
    location.updates.add(
      testFix(
        latitude: 37.5705,
        recordedAt: origin.add(const Duration(seconds: 16)),
      ),
    );
    await tester.pump();
    layer = tester.widget<RunMap>(layerFinder);
    expect(layer.segments, hasLength(2));
    expect(layer.segments.first.last.latitude, 37.567);
    expect(layer.segments.last.first.latitude, 37.57);
    await controller.finishRun();
    await tester.pump();
    expect(tester.widget<RunMap>(find.byType(RunMap)).segments, isEmpty);
    expect(find.text('현재 페이스'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('좁은 실제 화면에서도 측정값과 지도·종료 버튼이 겹치지 않습니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final controller = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    addTearDown(location.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: controller,
            mapBridgeFactory: FakeMapBridge.new,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(find.text('현재 페이스'), findsOneWidget);
    expect(find.text('평균 페이스'), findsOneWidget);
    expect(tester.getSize(find.byType(RunMap)).height, greaterThan(200));
    expect(find.text('러닝 종료').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    history.dispose();
  });

  testWidgets('화면 잠금 수명 주기 뒤에도 러닝 중 표시와 측정을 유지합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    final location = controller.locationService as FakeLocationService;
    location.fix = testFix(
      recordedAt: DateTime.now().subtract(const Duration(seconds: 8)),
    );
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    final session = controller.runSession!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    location.updates.add(testFix(latitude: 37.568));
    await tester.pump();
    expect(session.isRunning, isTrue);
    expect(session.distanceMeters, greaterThan(100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.runSession, same(session));
    expect(find.text('러닝 중'), findsOneWidget);
    expect(find.text('일시 정지'), findsWidgets);
    expect(controller.sharing, isFalse);
    expect(location.watchModes, [false, true]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('첫 GPS 응답이 없으면 시작을 실패 처리하고 백그라운드 측정을 해제합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    final location = controller.locationService as FakeLocationService;
    location.emitInitialFix = false;
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(controller.startingRun, isTrue);
    await tester.pump(const Duration(seconds: 21));
    expect(controller.startingRun, isFalse);
    expect(controller.runSession, isNull);
    expect(controller.runError, isNotNull);
    expect(location.activeWatches, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (size, scale) in [
    (const Size(320, 568), 1.0),
    (const Size(393, 852), 1.0),
    (const Size(430, 932), 1.0),
    (const Size(320, 568), 2.0),
  ]) {
    testWidgets('종료 창은 ${size.width} 너비와 ${scale}배 글자에서 동작합니다', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await showApp(tester, size, dark: scale == 2.0);
      await tester.ensureVisible(find.text('러닝 시작'));
      await tester.tap(find.text('러닝 시작'));
      await tester.pump();
      await tester.ensureVisible(find.text('러닝 종료'));
      if (scale == 2.0) {
        final pause = find.widgetWithText(FilledButton, '일시 정지');
        final finish = find.widgetWithText(OutlinedButton, '러닝 종료');
        expect(
          tester.getBottomLeft(pause).dy,
          lessThan(tester.getTopLeft(finish).dy),
        );
        final lock = find.byTooltip('조작 잠금');
        await tester.ensureVisible(lock);
        await tester.tap(lock);
        await tester.pump();
        final unlock = find.text('길게 눌러 해제');
        await tester.ensureVisible(unlock);
        await tester.longPress(unlock);
        await tester.pump();
        await tester.ensureVisible(finish);
      }
      await tester.tap(find.text('러닝 종료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('300m 미만 러닝은 저장되지 않습니다.'), findsOneWidget);
      expect(find.text('저장하고 종료'), findsNothing);
      final cancel = find.widgetWithText(TextButton, '취소');
      final finish = find.widgetWithText(FilledButton, '종료');
      expect(cancel.hitTestable(), findsOneWidget);
      expect(finish.hitTestable(), findsOneWidget);
      if (scale == 1.0) {
        expect(tester.getCenter(cancel).dy, tester.getCenter(finish).dy);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(finish);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('러닝 완료'), findsNothing);
      expect(find.text('기기에 저장됨'), findsNothing);
      expect(controller.runSession, isNull);
      expect(controller.runHistory.visibleRecords, isEmpty);
      expect((controller.runHistory.outbox as FakeRunOutbox).rows, isEmpty);
      expect(
        (controller.runHistory.service as FakeRunRecordService).attempts,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('오프라인으로 종료해도 기기 저장 결과를 표시하고 다시 시작합니다', (tester) async {
    final controller = await showApp(tester, const Size(320, 568));
    final service = controller.runHistory.service as FakeRunRecordService;
    service.saveFailure = const SocketException('오프라인');
    service.listFailure = const SocketException('오프라인');
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    restoreRecordableRun(controller);
    await tester.tap(find.text('러닝 종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('종료'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('기기에 저장됨'), findsOneWidget);
    expect(find.text('서버 저장 대기'), findsOneWidget);
    expect(controller.runSession, isNull);
    expect((controller.runHistory.outbox as FakeRunOutbox).rows, hasLength(1));
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
    expect(controller.runSession!.isRunning, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final offline in [false, true]) {
    testWidgets('러닝 종료 결과에서 바로 공유하고 홈으로 돌아옵니다: 오프라인 $offline', (tester) async {
      final controller = await showApp(
        tester,
        const Size(320, 568),
        recordService: ServerIdRecordService(),
      );
      final service = controller.runHistory.service as FakeRunRecordService;
      if (offline) {
        service.saveFailure = const SocketException('오프라인');
        service.listFailure = const SocketException('오프라인');
      }
      await tester.tap(find.text('러닝 시작'));
      await tester.pump();
      restoreRecordableRun(
        controller,
        route: RunRoute([
          [LatLng(37, 127), LatLng(37.0002, 127.0001)],
        ]),
      );
      await tester.tap(find.text('러닝 종료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('종료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(offline ? '기기에 저장됨' : '러닝 완료'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '이번 러닝 경로',
        ),
        findsOneWidget,
      );
      expect(find.text('공유 카드 만들기').hitTestable(), findsOneWidget);
      await tester.tap(find.text('공유 카드 만들기'));
      await tester.pump();
      final preview = find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == '공유 이미지 미리보기',
      );
      // 실제 PNG 렌더링 완료를 기다려 테스트 실행 부하에 영향을 받지 않습니다.
      for (
        var attempt = 0;
        attempt < 100 && preview.evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(preview, findsOneWidget);
      await tester.pumpAndSettle();
      final share = tester.widget<RunShareScreen>(find.byType(RunShareScreen));
      expect(share.record.pendingSync, offline);
      expect(share.record.temperature!.celsius, 20);
      expect(
        share.record.temperature!.observedAt,
        service.attempts.single.temperature!.observedAt,
      );
      if (!offline) expect(share.record.id, 'server-record-id');
      expect(
        share.record.clientRunId,
        controller.runHistory.visibleRecords.single.clientRunId,
      );
      expect(
        (await share.loadRoute()).toJson(),
        controller.runHistory.visibleRecords.single.route?.toJson() ??
            service.routes[share.record.id]!.toJson(),
      );
      expect(find.byTooltip('공유 설정'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('뒤로'));
      await tester.pumpAndSettle();
      expect(find.text('러닝 시작'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final offline in [false, true]) {
    testWidgets('러닝 종료 결과에 경험치 보상과 레벨 상승을 표시합니다: 오프라인 $offline', (
      tester,
    ) async {
      const levelUp = RunReward(
        xp: 70,
        levelBefore: 1,
        levelAfter: 2,
        progress: testProgress,
      );
      final progress = FakeProgressService(defaultReward: levelUp);
      final controller = await showApp(
        tester,
        const Size(320, 568),
        recordService: ServerIdRecordService(),
        progressService: progress,
      );
      final service = controller.runHistory.service as FakeRunRecordService;
      if (offline) {
        service.saveFailure = const SocketException('오프라인');
        service.listFailure = const SocketException('오프라인');
      }
      await tester.tap(find.text('러닝 시작'));
      await tester.pump();
      restoreRecordableRun(controller);
      await tester.tap(find.text('러닝 종료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('종료'));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('러닝 보상'), findsOneWidget);
      if (offline) {
        expect(find.text('서버에 저장되면 경험치가 지급돼요.'), findsOneWidget);
        expect(progress.rewardRequests, isEmpty);
      } else {
        expect(progress.rewardRequests, ['server-record-id']);
        expect(find.text('+70 XP'), findsOneWidget);
        expect(find.text('레벨 업!'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('프로필').last);
      await tester.pumpAndSettle();
      expect(find.text('새내기 러너'), findsOneWidget);
      expect(find.text('누적 130 XP'), findsOneWidget);
      expect(find.text('30 / 150 XP'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('프로필에 최신 러닝만 표시하고 상세 통계는 별도로 엽니다', (tester) async {
    final records = FakeRunRecordService();
    for (final (id, distance, day) in [
      ('recent', 2000, 20),
      ('older', 6400, 19),
    ]) {
      records.records.add(
        RunRecord(
          id: id,
          clientRunId: id,
          startedAt: DateTime.utc(2026, 11, day, 7),
          endedAt: DateTime.utc(2026, 11, day, 7, 20),
          distanceMeters: distance,
          durationSeconds: 1200,
        ),
      );
    }
    await showApp(
      tester,
      const Size(320, 568),
      recordService: records,
      statisticsService: FakeStatisticsService(),
    );
    await tester.tap(find.text('프로필').last);
    await tester.pumpAndSettle();
    expect(find.text('내 기록').hitTestable(), findsOneWidget);
    expect(find.text('주간 목표'), findsOneWidget);
    expect(find.text('2.00 km'), findsOneWidget);
    expect(find.text('6.40 km'), findsNothing);
    expect(find.text('누적 페이스'), findsNothing);
    final stats = find.text('러닝 통계');
    await tester.ensureVisible(stats);
    await tester.pumpAndSettle();
    await tester.tap(stats);
    await tester.pumpAndSettle();
    expect(find.text('누적 페이스'), findsOneWidget);
    expect(find.text('23회'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(320, 568), const Size(390, 844)]) {
    testWidgets('프로필에서 내 기록을 열고 돌아옵니다: ${size.width}', (tester) async {
      await showApp(tester, size);
      await tester.tap(find.text('프로필').last);
      await tester.pumpAndSettle();
      expect(find.text('내 기록').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('내 기록'));
      await tester.pumpAndSettle();
      expect(find.text('내 기록'), findsOneWidget);
      expect(find.text('아직 러닝 기록이 없습니다.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('최근 러닝'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(1280, 900),
    const Size(900, 500),
  ]) {
    testWidgets('지도와 버튼은 ${size.width} 너비에서도 겹치지 않습니다', (tester) async {
      await showApp(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.byType(RunMap), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _TourStore implements AppearanceStore {
  _TourStore(this.values);
  final Map<String, String> values;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
