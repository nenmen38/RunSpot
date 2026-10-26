import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/board_controller.dart';
import 'package:runquest/features/board/board_screen.dart';
import 'package:runquest/features/board/data/korean_regions.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:runquest/features/board/widgets/board_post_tile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_fakes.dart';

Widget boardApp(FakeBoardService service) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(18),
      child: BoardScreen(service: service),
    ),
  ),
);

void main() {
  group('BoardController', () {
    late FakeBoardService service;
    late BoardController controller;
    setUp(() {
      service = FakeBoardService();
      controller = BoardController(service);
    });
    tearDown(() => controller.dispose());

    test('게시판과 말머리를 바꾸면 조건에 맞게 다시 조회합니다', () async {
      await controller.refresh();
      controller.selectTopic(BoardTopic.food);
      await pumpEventQueue();
      controller.select(BoardKind.race);
      await pumpEventQueue();
      controller.selectTopic(BoardTopic.tip);
      await pumpEventQueue();
      expect(service.loads.map((call) => (call.kind, call.topic)), [
        (BoardKind.local, null),
        (BoardKind.local, BoardTopic.food),
        (BoardKind.race, null),
      ]);
    });

    test('늦게 도착한 이전 게시판 응답은 무시합니다', () async {
      final old = Completer<BoardFeed>();
      service.onLoad = (call) => call.kind == BoardKind.local
          ? old.future
          : Future.value(feed([postJson('n', board: 'national')]));
      final first = controller.refresh();
      controller.select(BoardKind.national);
      await pumpEventQueue();
      old.complete(feed([postJson('old')]));
      await first;
      expect(controller.posts.single.id, 'n');
    });

    test('더 보기는 다음 기준으로 이어 붙이고 중복을 제외합니다', () async {
      service.onLoad = (call) => Future.value(
        call.before == null
            ? feed([postJson('1'), postJson('2')], next: {'at': 't', 'id': '2'})
            : feed([postJson('2'), postJson('3')]),
      );
      await controller.refresh();
      expect(controller.hasMore, isTrue);
      await controller.loadMore();
      expect(service.loads.last.before?.id, '2');
      expect(controller.posts.map((post) => post.id), ['1', '2', '3']);
      expect(controller.hasMore, isFalse);
    });

    test('동네 미설정과 작성 권한을 구분합니다', () async {
      service.onLoad = (_) => Future.value(feed(const [], region: null));
      await controller.refresh();
      expect(controller.needsRegion, isTrue);
      expect(controller.canCreate, isFalse);
      await controller.changeRegion('서울특별시 강남구');
      expect(service.savedRegion, '서울특별시 강남구');

      service.onLoad = (_) => Future.value(feed(const [], canPostRace: false));
      controller.select(BoardKind.race);
      await pumpEventQueue();
      expect(controller.canCreate, isFalse);
    });

    test('서버 거절 문구를 그대로 안내하고 계정이 바뀌면 목록을 지웁니다', () async {
      service.onLoad = (_) => Future.value(feed([postJson('1')]));
      await controller.refresh();
      service.createError = const PostgrestException(
        message: '잠시 후 다시 작성해 주세요.',
        code: 'P0001',
      );
      final error = await controller.create(
        const BoardDraft(
          clientId: 'c',
          kind: BoardKind.local,
          title: '제목',
          body: '내용',
          topic: BoardTopic.tip,
        ),
      );
      expect(error, '잠시 후 다시 작성해 주세요.');

      service.owner = false;
      await controller.refresh();
      expect(controller.posts, isEmpty);
      expect(controller.error, '다시 로그인해 주세요.');
    });
  });

  test('글과 대회 공지를 해석합니다', () {
    final post = BoardPost.fromJson(
      postJson(
        'r',
        board: 'race',
        topic: null,
        region: null,
        raceDate: '2026-11-08',
      ),
    );
    expect(post.kind, BoardKind.race);
    expect(post.topic, isNull);
    expect(post.raceDate, DateTime(2026, 11, 8));
    expect(formatRaceDate(DateTime(2026, 11, 8)), '2026.11.8 (일)');
    expect(
      raceCountdown(DateTime(2026, 11, 8), now: DateTime(2026, 10, 26, 23)),
      'D-13',
    );
    expect(
      raceCountdown(DateTime(2026, 10, 26), now: DateTime(2026, 10, 26, 9)),
      'D-DAY',
    );
    expect(
      formatBoardTime(
        DateTime(2026, 10, 26, 9),
        now: DateTime(2026, 10, 26, 11),
      ),
      '2시간 전',
    );
  });

  test('동네 목록은 서버 형식과 일치합니다', () {
    final pattern = RegExp(r'^[가-힣]{2,10}( [가-힣]{1,10})?$');
    for (final MapEntry(key: province, value: districts)
        in koreanRegions.entries) {
      for (final district in districts.isEmpty ? <String?>[null] : districts) {
        expect(pattern.hasMatch(regionLabel(province, district)), isTrue);
      }
      expect(districts.toSet().length, districts.length, reason: province);
    }
    expect(koreanRegions.length, 17);
  });

  testWidgets('동네를 설정하면 동네 글을 보여줍니다', (tester) async {
    final service = FakeBoardService();
    service.onLoad = (_) => Future.value(
      service.savedRegion == null
          ? feed(const [], region: null)
          : feed([postJson('1')], region: service.savedRegion),
    );
    await tester.pumpWidget(boardApp(service));
    await tester.pumpAndSettle();
    expect(find.text('동네 설정하기'), findsOneWidget);
    expect(find.text('글쓰기'), findsNothing);

    await tester.tap(find.text('동네 설정하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('서울특별시'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('강남구'));
    await tester.pumpAndSettle();
    expect(service.savedRegion, '서울특별시 강남구');
    expect(find.text('서울특별시 강남구'), findsOneWidget);
    expect(find.text('제목1'), findsOneWidget);
    expect(find.text('글쓰기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('글쓰기는 말머리와 제목을 확인한 뒤 등록합니다', (tester) async {
    final service = FakeBoardService();
    await tester.pumpWidget(boardApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('글쓰기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    expect(find.text('말머리를 선택해 주세요.'), findsOneWidget);
    expect(find.text('제목을 입력해 주세요.'), findsOneWidget);
    expect(service.created, isEmpty);

    await tester.tap(find.text('맛집'));
    await tester.enterText(
      find.widgetWithText(TextFormField, '제목'),
      ' 부산 돼지국밥 ',
    );
    await tester.enterText(find.widgetWithText(TextFormField, '내용'), '러닝 후 추천');
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    final draft = service.created.single;
    expect(draft.kind, BoardKind.national);
    expect(draft.topic, BoardTopic.food);
    expect(draft.title, '부산 돼지국밥');
    expect(find.text('러닝 대회'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('러닝 대회 공지는 관리자에게만 등록 버튼을 보여줍니다', (tester) async {
    final service = FakeBoardService();
    var staff = false;
    service.onLoad = (call) => Future.value(
      feed(
        call.kind == BoardKind.race
            ? [
                postJson(
                  'r',
                  board: 'race',
                  topic: null,
                  region: null,
                  raceDate: '2099-11-08',
                ),
              ]
            : const [],
        canPostRace: staff,
      ),
    );
    await tester.pumpWidget(boardApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('러닝 대회'));
    await tester.pumpAndSettle();
    expect(find.text('광화문'), findsOneWidget);
    expect(find.text('공지 등록'), findsNothing);
    expect(find.text('추천 코스'), findsNothing);

    staff = true;
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('러닝 대회'));
    await tester.pumpAndSettle();
    expect(find.text('공지 등록'), findsOneWidget);

    await tester.tap(find.text('제목r'));
    await tester.pumpAndSettle();
    expect(find.text('대회 안내 페이지 열기'), findsOneWidget);
    expect(find.byTooltip('삭제'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
