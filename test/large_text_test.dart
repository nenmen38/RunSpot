import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:runquest/app/mobile_app_viewport.dart';
import 'package:runquest/app/run_quest_shell.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/run_conditions/conditions_controller.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/conditions_fakes.dart';
import 'support/friend_fakes.dart';
import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';
import 'support/statistics_fakes.dart';

class _Storage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async =>
      values[key] = value;
  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
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
        pkceAsyncStorage: _Storage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(null),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  // 폰 글자 크기를 가장 크게(2배) 하고 앱의 '아주 크게'(1.3배)까지 겹쳐도 넘치지 않아야 합니다.
  testWidgets('작은 폰에서 아주 큰 글씨(2.6배)로도 모든 탭이 넘치지 않습니다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.reset);
    final location = FakeLocationService();
    addTearDown(location.updates.close);
    final map = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: RunHistoryController(
        FakeRunRecordService(),
        outbox: FakeRunOutbox(),
      ),
    );
    final conditions = ConditionsController(FakeConditionsService());
    addTearDown(conditions.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MobileAppViewport(
          child: RunQuestShell(
            mapController: map,
            mapBridgeFactory: FakeMapBridge.new,
            friendService: FakeFriendService(),
            rankingService: FakeRankingService(),
            conditionsController: conditions,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '홈');
    for (final tab in ['소셜', '프로필', '게시판', '아이템']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: tab);
      // 아래로 내려 가며 그려지는 내용도 확인합니다.
      for (var i = 0; i < 8; i++) {
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isEmpty) break;
        await tester.drag(
          scrollables.first,
          const Offset(0, -500),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab 스크롤');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
