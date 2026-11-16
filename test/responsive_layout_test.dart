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

/// 작은 폰, 일반 폰, 폴드 겉화면, 폴드 펼친 화면(세로·가로)입니다.
const sizes = {
  '작은 폰': Size(320, 568),
  '일반 폰': Size(360, 780),
  '폴드 겉화면': Size(411, 960),
  '폴드 펼침 세로': Size(750, 832),
  '폴드 펼침 가로': Size(832, 750),
};

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

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets(
      '$name(${size.width.toInt()}×${size.height.toInt()})에서 모든 탭이 화면 안에 들어옵니다',
      (tester) async {
        // 실제 기기처럼 화면 크기(MediaQuery 포함)를 맞춥니다.
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
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
        expect(tester.takeException(), isNull, reason: '$name 홈');
        // 폴드를 펼친 넓은 화면만 메뉴를 왼쪽 세로로 둡니다.
        final wide = size.width >= 600;
        expect(
          find.byType(NavigationRail),
          wide ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(NavigationBar),
          wide ? findsNothing : findsOneWidget,
        );
        for (final tab in ['소셜', '프로필', '게시판', '아이템', '홈']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$name $tab');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
