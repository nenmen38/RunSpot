import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:runquest/shared/maps/run_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:runquest/app/mobile_app_viewport.dart';
import 'package:runquest/app/run_quest_shell.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/models/run_session.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_share/run_share_screen.dart';
import 'package:runquest/features/run_conditions/conditions_controller.dart';

import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';
import 'support/friend_fakes.dart';
import 'support/conditions_fakes.dart';

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

void main() {
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
              ? 'false'
              : jsonEncode({'visibility': 'private', 'nickname': null}),
          200,
          headers: {'content-type': 'application/json'},
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
  }) async {
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
        theme: ThemeData(useMaterial3: true),
        home: MobileAppViewport(
          child: RunQuestShell(
            mapController: controller,
            mapBridgeFactory: FakeMapBridge.new,
            friendService: FakeFriendService(),
            conditionsController: conditions,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('홈은 현재 위치 지도이며 코스 만들기 탭이 없습니다', (tester) async {
    await showApp(tester, const Size(390, 844));
    expect(find.byType(RunMap), findsOneWidget);
    expect(
      tester.widget<RunMap>(find.byType(RunMap)).controller.camera.zoom,
      15.5,
    );
    expect(find.text('RunSpot'), findsNothing);
    expect(find.byTooltip('주변 러너 조회 반경'), findsNothing);
    expect(find.byTooltip('내 기록'), findsNothing);
    expect(find.byTooltip('프로필 및 공개 설정'), findsNothing);
    expect(find.bySemanticsLabel('내 현재 위치'), findsOneWidget);
    expect(find.text('위치 공유'), findsOneWidget);
    expect(find.text('러닝 조건 양호'), findsOneWidget);
    expect(find.text('러닝 시작'), findsOneWidget);
    expect(find.text('러닝 종료'), findsOneWidget);
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
    expect(find.text('0.00 km'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('내 프로필'), findsOneWidget);
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

  testWidgets('다른 탭을 다녀와도 지도와 공유 상태를 유지합니다', (tester) async {
    final controller = await showApp(tester, const Size(390, 844));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(controller.sharing, isTrue);
    await tester.tap(find.text('소셜').last);
    await tester.pumpAndSettle();
    expect(find.text('내 친구 0'), findsOneWidget);
    await tester.tap(find.text('랭킹'));
    await tester.pumpAndSettle();
    expect(find.text('친구 랭킹'), findsOneWidget);
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

  testWidgets('오프라인으로 종료해도 기기 저장 결과를 표시하고 다시 시작합니다', (tester) async {
    final controller = await showApp(tester, const Size(320, 568));
    final service = controller.runHistory.service as FakeRunRecordService;
    service.saveFailure = const SocketException('오프라인');
    service.listFailure = const SocketException('오프라인');
    await tester.tap(find.text('러닝 시작'));
    await tester.pump();
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
      await tester.tap(find.text('러닝 종료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('종료'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(offline ? '기기에 저장됨' : '러닝 완료'), findsOneWidget);
      expect(find.text('공유').hitTestable(), findsOneWidget);
      await tester.tap(find.text('공유'));
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
      expect(find.text('내 프로필'), findsOneWidget);
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
