import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:runquest/features/board/board_comments_controller.dart';
import 'package:runquest/features/board/board_controller.dart';
import 'package:runquest/features/board/board_screen.dart';
import 'package:runquest/features/board/data/board_photo_service.dart';
import 'package:runquest/features/board/models/board_post.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_fakes.dart';

final _png = img.encodePng(img.Image(width: 4, height: 4));

Widget boardApp(FakeBoardService service, FakeBoardPhotoService photos) =>
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(18),
          child: BoardScreen(service: service, photoService: photos),
        ),
      ),
    );

void main() {
  test('좋아요는 서버가 돌려준 상태와 개수로 바꿉니다', () async {
    final service = FakeBoardService()..likeCount = 2;
    service.onLoad = (_) => Future.value(feed([postJson('1', likeCount: 2)]));
    final controller = BoardController(service);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(await controller.setLike(controller.posts.single, true), isNull);
    expect(controller.posts.single.liked, isTrue);
    expect(controller.posts.single.likeCount, 3);
    controller.updateCommentCount('1', 4);
    expect(controller.postById('1')!.commentCount, 4);
  });

  test('본인 글을 지우면 첨부 사진도 정리합니다', () async {
    final service = FakeBoardService();
    service.onLoad = (_) => Future.value(
      feed([
        postJson('1', isMine: true, images: ['owner/a.jpg']),
      ]),
    );
    final controller = BoardController(service);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(await controller.delete(controller.posts.single), isNull);
    await pumpEventQueue();
    expect(service.deleted, ['1']);
    expect(service.removedPhotos, ['owner/a.jpg']);
  });

  test('댓글은 같은 내용으로 다시 보내면 같은 식별자를 씁니다', () async {
    final service = FakeBoardService()
      ..commentError = const PostgrestException(
        message: '잠시 후 다시 작성해 주세요.',
        code: 'P0001',
      );
    final counts = <int>[];
    final comments = BoardCommentsController(service, '1', onCount: counts.add);
    addTearDown(comments.dispose);
    expect(await comments.add('  '), '댓글을 입력해 주세요.');
    expect(await comments.add(' 좋아요 '), '잠시 후 다시 작성해 주세요.');
    service.commentError = null;
    expect(await comments.add('좋아요'), isNull);
    expect(service.addedComments[0].$1, service.addedComments[1].$1);
    expect(service.addedComments.last.$2, '좋아요');
    expect(await comments.add('다른 댓글'), isNull);
    expect(service.addedComments.last.$1, isNot(service.addedComments[0].$1));
    expect(comments.comments, hasLength(2));
    expect(counts.last, 2);
  });

  testWidgets('사진을 다시 저장해 촬영 위치와 기기 정보를 지웁니다', (tester) async {
    final source = img.Image(width: 2400, height: 1200);
    img.fill(source, color: img.ColorRgb8(30, 120, 220));
    source.exif.imageIfd['Make'] = 'TestPhone';
    source.exif.gpsIfd['GPSLatitudeRef'] = 'N';
    final original = img.encodeJpg(source);
    expect(img.decodeJpg(original)!.exif.isEmpty, isFalse);

    final result = await tester.runAsync(() => encodeBoardPhoto(original));
    final decoded = img.decodeJpg(result!)!;
    expect(decoded.exif.isEmpty, isTrue);
    expect(decoded.width, boardPhotoMaxSide);
    expect(decoded.height, 800);
    final failure = await tester.runAsync(() async {
      try {
        await encodeBoardPhoto(Uint8List.fromList([1, 2, 3]));
        return null;
      } on BoardPhotoException catch (error) {
        return error;
      }
    });
    expect(failure, isA<BoardPhotoException>());
  });

  testWidgets('글쓰기에서 키보드 이모지와 사진을 넣고 사진을 올린 뒤 등록합니다', (tester) async {
    final service = FakeBoardService();
    final photos = FakeBoardPhotoService()..next = [_png, _png];
    await tester.pumpWidget(boardApp(service, photos));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('글쓰기'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('꿀 정보'));
    await tester.enterText(find.widgetWithText(TextFormField, '제목'), '새벽 러닝');
    // 정해진 이모지 목록 없이 키보드로 입력한 이모지를 그대로 저장합니다.
    expect(find.byKey(const ValueKey('emoji')), findsNothing);
    await tester.enterText(find.widgetWithText(TextFormField, '내용'), '상쾌해요🔥');
    await tester.tap(find.text('사진 추가'));
    await tester.pumpAndSettle();
    expect(photos.limits.single, 4);
    expect(find.text('사진 2/4'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('사진 1/4'), findsOneWidget);

    await tester.ensureVisible(find.text('등록'));
    await tester.tap(find.text('등록'));
    await tester.pumpAndSettle();
    final draft = service.created.single;
    expect(draft.body, '상쾌해요🔥');
    expect(draft.images, ['owner/1.jpg']);
    expect(service.uploads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('글 상세에서 좋아요·댓글·수정을 사용합니다', (tester) async {
    final service = FakeBoardService();
    service.onLoad = (_) => Future.value(
      feed([
        postJson('1', board: 'national', isMine: true, images: ['owner/a.jpg']),
      ]),
    );
    service.commentRows = [commentJson('x')];
    await tester.pumpWidget(boardApp(service, FakeBoardPhotoService()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제목1'));
    await tester.pumpAndSettle();

    expect(find.text('댓글x'), findsOneWidget);
    expect(find.text('댓글 1'), findsOneWidget);
    await tester.tap(find.text('좋아요 0'));
    await tester.pumpAndSettle();
    expect(find.text('좋아요 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '같이 뛰어요 🏃');
    await tester.tap(find.byTooltip('댓글 등록'));
    await tester.pumpAndSettle();
    expect(service.addedComments.single.$2, '같이 뛰어요 🏃');
    expect(find.text('댓글 2'), findsOneWidget);

    await tester.tap(find.byTooltip('게시글 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    expect(find.text('글 수정'), findsOneWidget);
    expect(find.text('사진 1/4'), findsOneWidget);
    await tester.tap(find.text('맛집'));
    await tester.enterText(find.widgetWithText(TextFormField, '제목'), '고친 제목');
    await tester.ensureVisible(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('사진 0/4'), findsOneWidget);
    await tester.ensureVisible(find.text('수정 완료'));
    await tester.tap(find.text('수정 완료'));
    await tester.pumpAndSettle();
    final draft = service.updated.single;
    expect(draft.topic, BoardTopic.food);
    expect(draft.title, '고친 제목');
    expect(draft.images, isEmpty);
    expect(service.removedPhotos, ['owner/a.jpg']);
    expect(service.uploads, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('댓글 권한이 없으면 입력창을 숨깁니다', (tester) async {
    final service = FakeBoardService()..canComment = false;
    service.onLoad = (_) =>
        Future.value(feed([postJson('1', board: 'national')]));
    await tester.pumpWidget(boardApp(service, FakeBoardPhotoService()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전국'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제목1'));
    await tester.pumpAndSettle();
    expect(find.text('아직 댓글이 없어요.'), findsOneWidget);
    expect(find.byTooltip('댓글 등록'), findsNothing);
    await tester.tap(find.byTooltip('게시글 메뉴'));
    await tester.pumpAndSettle();
    expect(find.text('수정'), findsNothing);
    expect(find.text('신고'), findsOneWidget);
  });
}
