import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_share/data/run_share_service.dart';
import 'package:runquest/features/run_share/data/share_image_renderer.dart';
import 'package:runquest/features/run_share/data/share_photo_service.dart';
import 'package:runquest/features/run_history/models/run_temperature.dart';
import 'package:runquest/features/run_share/models/share_route.dart';
import 'package:runquest/features/run_share/run_share_screen.dart';

import 'share_photo_test.dart' show photoBytes;

import 'package:runquest/features/run_share/models/share_layout.dart';

final record = RunRecord(
  id: 'private-id',
  clientRunId: 'private-client',
  startedAt: DateTime.utc(2026),
  endedAt: DateTime.utc(2026, 1, 1, 1),
  distanceMeters: 5000,
  durationSeconds: 1500,
);
final route = RunRoute([List.generate(60, (i) => LatLng(37 + i * .0002, 127))]);
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1cAAAAASUVORK5CYII=',
);

class Renderer extends ShareImageRenderer {
  final options = <({ShareRoute? route})>[];
  bool fail = false;
  ui.Image? background;
  bool dark = false;
  double height = 0;
  Color? textColor;
  bool photoOverlay = false;
  ShareLayout selectedLayout = ShareLayout.centered;
  @override
  Future<Uint8List> render(
    RunRecord record, {
    ShareRoute? route,
    ui.Image? background,
    bool dark = false,
    double height = 1920,
    Color? textColor,
    bool photoOverlay = false,
    ShareLayout layout = ShareLayout.centered,
  }) async {
    options.add((route: route));
    this.height = height;
    this.textColor = textColor;
    this.photoOverlay = photoOverlay;
    selectedLayout = layout;
    this.background = background;
    this.dark = dark;
    if (fail) throw StateError('실패');
    return png;
  }
}

class Photos implements SharePhotoService {
  ui.Image? photo;
  Object? error;
  Completer<ui.Image?>? pending;
  int calls = 0;
  @override
  Future<ui.Image?> pick() async {
    calls++;
    if (error != null) throw error!;
    return pending == null ? photo : pending!.future;
  }
}

class ShareService implements RunShareService {
  int calls = 0;
  bool fail = false;
  Rect? origin;
  final response = Completer<RunShareResult>();
  @override
  Future<RunShareResult> share(
    Uint8List png,
    Rect origin, {
    required bool Function() isCurrentOwner,
  }) async {
    if (!isCurrentOwner()) throw StateError('계정 전환');
    calls++;
    this.origin = origin;
    if (fail) throw StateError('플러그인 실패');
    return response.future;
  }
}

void main() {
  test('계정이 바뀌면 플랫폼 공유 파일을 만들거나 공유창을 열지 않습니다', () async {
    await expectLater(
      PlatformRunShareService().share(
        png,
        const Rect.fromLTWH(0, 0, 100, 40),
        isCurrentOwner: () => false,
      ),
      throwsStateError,
    );
  });
  test('빈 경로와 정지한 경로는 공유 선을 만들지 않습니다', () {
    expect(ShareRoute.shape(const RunRoute.empty()).isEmpty, isTrue);
    expect(
      ShareRoute.shape(
        RunRoute([
          [const LatLng(37, 127), const LatLng(37, 127)],
        ]),
      ).isEmpty,
      isTrue,
    );
  });
  testWidgets('300m의 짧은 기록도 공유 이미지에 경로 선을 그립니다', (tester) async {
    final shortRoute = RunRoute([
      List.generate(16, (i) => LatLng(37 + i * .00018, 127)),
    ]);
    final shape = ShareRoute.shape(shortRoute);
    expect(shape.segments.single, hasLength(16));
    await tester.runAsync(() async {
      final bytes = await ShareImageRenderer().render(record, route: shape);
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      try {
        final pixels = (await image.toByteData())!.buffer.asUint8List();
        final index = (500 * 1080 + 540) * 4;
        expect(pixels.sublist(index, index + 3), [32, 36, 40]);
      } finally {
        image.dispose();
        codec.dispose();
      }
    });
  });
  test('전체 경로를 좌표 정보 없는 0~1의 선 모양으로 정규화합니다', () {
    final shape = ShareRoute.shape(route);
    expect(shape.segments.single.length, equals(route.segments.single.length));
    expect(shape.isEmpty, isFalse);
    for (final point in shape.segments.expand((s) => s)) {
      expect(point.dx, inInclusiveRange(0, 1));
      expect(point.dy, inInclusiveRange(0, 1));
    }
  });
  test('단절과 긴 좌표 간격은 연결하지 않습니다', () {
    final segment = route.segments.single;
    final interrupted = RunRoute([segment.take(30), segment.skip(32)]);
    expect(ShareRoute.shape(interrupted).segments, hasLength(2));
    final crossing = RunRoute([
      segment
          .take(30)
          .followedBy([const LatLng(37, 127)])
          .followedBy(segment.skip(32)),
    ]);
    expect(ShareRoute.shape(crossing).segments, hasLength(2));
  });
  testWidgets('PNG는 1080px이며 식별자·날짜·선택하지 않은 경로를 담지 않습니다', (tester) async {
    await tester.runAsync(() async {
      final renderer = ShareImageRenderer();
      final bytes = await renderer.render(record);
      final other = RunRecord(
        id: 'other',
        clientRunId: 'other',
        startedAt: DateTime.utc(2030),
        endedAt: DateTime.utc(2030, 1, 1, 1),
        distanceMeters: 5000,
        durationSeconds: 1500,
        route: route,
      );
      expect(await renderer.render(other), bytes);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1080);
      expect(frame.image.height, 1920);
      final pixels = await frame.image.toByteData();
      expect(pixels!.buffer.asUint8List().toSet().length, greaterThan(8));
      frame.image.dispose();
      codec.dispose();
      final full = await renderer.render(
        record,
        route: ShareRoute.shape(route),
        height: 2341,
      );
      final fullCodec = await ui.instantiateImageCodec(full);
      final fullFrame = await fullCodec.getNextFrame();
      expect(fullFrame.image.height, 2341);
      fullFrame.image.dispose();
      fullCodec.dispose();
    });
  });
  Future<void> show(
    WidgetTester tester,
    Renderer renderer, {
    ShareService? service,
    bool Function()? owner,
    Stream<Object?>? changes,
    Future<RunRoute> Function()? loadRoute,
    SharePhotoService? photos,
    bool settings = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RunShareScreen(
          record: record,
          isCurrentOwner: owner ?? () => true,
          loadRoute: loadRoute ?? () => Future.value(route),
          renderer: renderer,
          shareService: service,
          ownerChanges: changes,
          photoService: photos,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (settings) {
      await tester.tap(find.byTooltip('공유 설정'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('갤러리 배경 적용·기본 복원·취소·오류를 처리합니다', (tester) async {
    final renderer = Renderer();
    final photos = Photos();
    photos.photo = await tester.runAsync(
      () async => decodeSharePhoto(await photoBytes()),
    );
    await show(tester, renderer, photos: photos, settings: true);
    await tester.tap(find.byTooltip('갤러리 사진 선택'));
    await tester.pumpAndSettle();
    expect(renderer.background, same(photos.photo));
    expect(renderer.photoOverlay, isFalse);
    await tester.tap(find.text('사진 배경 덮개'));
    await tester.pumpAndSettle();
    expect(renderer.photoOverlay, isTrue);
    await tester.tap(find.text('사진 배경 덮개'));
    await tester.pumpAndSettle();
    expect(renderer.photoOverlay, isFalse);
    photos.photo = null;
    await tester.tap(find.byTooltip('갤러리 사진 선택'));
    await tester.pumpAndSettle();
    expect(renderer.background, isNotNull);
    photos.error = const SharePhotoException('사진 권한 확인');
    await tester.tap(find.byTooltip('갤러리 사진 선택'));
    await tester.pumpAndSettle();
    expect(find.text('사진 권한 확인'), findsWidgets);
    expect(renderer.background, isNotNull);
    await tester.tap(find.byTooltip('어두운 기본 배경'));
    await tester.pumpAndSettle();
    expect(renderer.background, isNull);
    expect(find.text('사진 배경 덮개'), findsNothing);
    expect(renderer.dark, isTrue);
    await tester.tap(find.byTooltip('밝은 기본 배경'));
    await tester.pumpAndSettle();
    expect(renderer.dark, isFalse);
  });
  testWidgets('사진 선택 중 계정이 바뀌면 결과를 폐기하고 중복 선택을 막습니다', (tester) async {
    final renderer = Renderer();
    final photos = Photos()..pending = Completer<ui.Image?>();
    var owner = true;
    final changes = StreamController<Object?>.broadcast();
    addTearDown(changes.close);
    await show(
      tester,
      renderer,
      photos: photos,
      owner: () => owner,
      changes: changes.stream,
      settings: true,
    );
    await tester.tap(find.byTooltip('갤러리 사진 선택'));
    await tester.pump();
    await tester.tap(find.byTooltip('갤러리 사진 선택'));
    expect(photos.calls, 1);
    owner = false;
    changes.add(null);
    await tester.pump();
    final photo = await tester.runAsync(
      () async => decodeSharePhoto(await photoBytes()),
    );
    photos.pending!.complete(photo);
    await tester.pumpAndSettle();
    expect(renderer.background, isNull);
    expect(find.text('로그인 상태를 확인해 주세요.'), findsWidgets);
  });
  testWidgets('기온·사진은 실제 PNG 픽셀에 반영되며 원본 바이트를 공유하지 않습니다', (tester) async {
    await tester.runAsync(() async {
      final renderer = ShareImageRenderer();
      final photo = await decodeSharePhoto(await photoBytes());
      try {
        final withTemperature = RunRecord(
          id: record.id,
          clientRunId: record.clientRunId,
          startedAt: record.startedAt,
          endedAt: record.endedAt,
          distanceMeters: 5000,
          durationSeconds: 1500,
          temperature: RunTemperature(
            celsius: 23.5,
            observedAt: record.endedAt,
          ),
        );
        final bytes = await renderer.render(withTemperature, background: photo);
        expect(bytes, isNot(await photoBytes()));
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 1080);
        expect(image.height, 1920);
        final pixels = (await image.toByteData())!.buffer.asUint8List();
        final index = (700 * 1080 + 1000) * 4;
        expect(pixels[index], greaterThan(pixels[index + 1]));
        expect(pixels[index], lessThan(255));
        final backgroundIndex = (100 * 1080 + 1000) * 4;
        expect(pixels[backgroundIndex], 244);
        expect(pixels[backgroundIndex + 1], 67);
        expect(pixels[backgroundIndex + 2], 54);
        image.dispose();
        codec.dispose();
        expect(
          await renderer.render(record, dark: true),
          isNot(await renderer.render(record)),
        );
      } finally {
        photo.dispose();
      }
    });
  });

  testWidgets('기록과 선택한 경로 묶음은 세로 화면의 중앙에 배치됩니다', (tester) async {
    await tester.runAsync(() async {
      for (final height in [1512.0, 1920.0, 2341.0]) {
        for (final includeRoute in [false, true]) {
          final bytes = await ShareImageRenderer().render(
            record,
            height: height,
            route: includeRoute ? ShareRoute.shape(route) : null,
          );
          final codec = await ui.instantiateImageCodec(bytes);
          final image = (await codec.getNextFrame()).image;
          try {
            final pixels = (await image.toByteData())!.buffer.asUint8List();
            var first = image.height;
            var last = -1;
            for (var y = 0; y < image.height; y++) {
              for (var x = 0; x < image.width; x++) {
                final i = (y * image.width + x) * 4;
                if (pixels[i] != 248 ||
                    pixels[i + 1] != 250 ||
                    pixels[i + 2] != 252) {
                  if (y < first) first = y;
                  last = y;
                  break;
                }
              }
            }
            expect(last, greaterThan(first));
            expect((first + last) / 2, closeTo(height / 2, 24));
          } finally {
            image.dispose();
            codec.dispose();
          }
        }
      }
    });
  });

  testWidgets('사진 덮개는 선택했을 때만 적용하고 글자 색에 맞춰 밝기를 보정합니다', (tester) async {
    await tester.runAsync(() async {
      final renderer = ShareImageRenderer();
      final photo = await decodeSharePhoto(await photoBytes());
      try {
        for (final color in [Colors.white, Colors.black]) {
          final bytes = await renderer.render(
            record,
            background: photo,
            textColor: color,
            photoOverlay: true,
          );
          final codec = await ui.instantiateImageCodec(bytes);
          final image = (await codec.getNextFrame()).image;
          try {
            final pixels = (await image.toByteData())!.buffer.asUint8List();
            final index = (100 * 1080 + 1000) * 4;
            final expected = Color.alphaBlend(
              color == Colors.white
                  ? const Color(0x8C000000)
                  : const Color(0x8CFFFFFF),
              Colors.red,
            );
            expect(pixels[index], closeTo((expected.r * 255).round(), 2));
            expect(pixels[index + 1], closeTo((expected.g * 255).round(), 2));
            expect(pixels[index + 2], closeTo((expected.b * 255).round(), 2));
          } finally {
            image.dispose();
            codec.dispose();
          }
        }
        expect(
          await renderer.render(record, photoOverlay: true),
          await renderer.render(record),
        );
      } finally {
        photo.dispose();
      }
    });
  });

  testWidgets('공유 설정은 AI 피드백 없이 경로 공개 여부만 선택합니다', (tester) async {
    final renderer = Renderer();
    var routes = 0;
    await show(
      tester,
      renderer,
      settings: true,
      loadRoute: () async {
        routes++;
        return route;
      },
    );
    expect(renderer.options.single.route, isNull);
    expect(routes, 0);
    expect(find.text('AI 피드백 포함'), findsNothing);
    expect(find.text('RunSpot'), findsNothing);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(
      tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .every((s) => !s.value),
      isTrue,
    );
  });

  test('모든 템플릿은 화면 비율과 경로 유무에 관계없이 이미지 안에 배치됩니다', () {
    for (final height in [1512.0, 1920.0, 2341.0, 3240.0]) {
      for (final layout in ShareLayout.values) {
        for (final hasRoute in [false, true]) {
          final composition = layout.compose(height, hasRoute: hasRoute);
          for (final bounds in [
            ...composition.texts.map((slot) => slot.rect),
            if (composition.route != null) composition.route!,
            if (composition.panel != null) composition.panel!,
          ]) {
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.top, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(1080));
            expect(bounds.bottom, lessThanOrEqualTo(height));
          }
        }
      }
    }
  });
  testWidgets('다섯 공유 템플릿을 선택하면 이미지에 반영합니다', (tester) async {
    final renderer = Renderer();
    await show(tester, renderer, settings: true);
    for (final layout in ShareLayout.values) {
      final chip = find.widgetWithText(ChoiceChip, layout.label);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(renderer.selectedLayout, layout);
    }
  });
  testWidgets('다섯 템플릿은 서로 다른 이미지를 생성합니다', (tester) async {
    await tester.runAsync(() async {
      final images = <Uint8List>[];
      for (final layout in ShareLayout.values) {
        final image = await ShareImageRenderer().render(
          record,
          route: ShareRoute.shape(route),
          layout: layout,
        );
        for (final previous in images) {
          expect(image, isNot(previous));
        }
        images.add(image);
      }
    });
  });
  testWidgets('글자 색 견본·직접 입력·취소·자동 복원을 공유 이미지에 반영합니다', (tester) async {
    final renderer = Renderer();
    await show(tester, renderer, settings: true);
    await tester.tap(find.byTooltip('글자 색 하늘'));
    await tester.pumpAndSettle();
    expect(renderer.textColor, const Color(0xFF9FE7FF));
    await tester.tap(find.byTooltip('사용자 지정 글자 색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#22AA88');
    await tester.pump();
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(renderer.textColor, const Color(0xFF22AA88));
    await tester.tap(find.byTooltip('사용자 지정 글자 색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#12');
    await tester.pump();
    expect(find.text('여섯 자리 색상 코드를 입력해 주세요.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('적용'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(renderer.textColor, const Color(0xFF22AA88));
    await tester.tap(find.byTooltip('자동 글자 색'));
    await tester.pumpAndSettle();
    expect(renderer.textColor, isNull);
  });

  testWidgets('글자 색은 유지하고 사진과 낮은 대비에서도 글씨 테두리를 그리지 않습니다', (tester) async {
    await tester.runAsync(() async {
      Future<Uint8List> pixels(Color color, {ui.Image? photo}) async {
        final bytes = await ShareImageRenderer().render(
          record,
          textColor: color,
          background: photo,
        );
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        try {
          return (await image.toByteData())!.buffer.asUint8List();
        } finally {
          image.dispose();
          codec.dispose();
        }
      }

      int count(Uint8List data, int r, int g, int b) {
        var n = 0;
        for (var i = 0; i < data.length; i += 4) {
          if (data[i] == r && data[i + 1] == g && data[i + 2] == b) n++;
        }
        return n;
      }

      expect(
        count(await pixels(const Color(0xFF1540A0)), 21, 64, 160),
        greaterThan(500),
      );
      expect(count(await pixels(Colors.white), 23, 26, 29), 0);
      final photo = await decodeSharePhoto(await photoBytes());
      try {
        final data = await pixels(const Color(0xFF171A1D), photo: photo);
        final index = (100 * 1080 + 1000) * 4;
        expect(data[index], 244);
        expect(data[index + 1], 67);
        expect(count(data, 255, 255, 255), 0);
      } finally {
        photo.dispose();
      }
    });
  });

  testWidgets('색상 슬라이더도 색상 코드와 최종 글자 색을 함께 바꿉니다', (tester) async {
    final renderer = Renderer();
    await show(tester, renderer, settings: true);
    await tester.tap(find.byTooltip('사용자 지정 글자 색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#FF0000');
    await tester.pump();
    tester.widgetList<Slider>(find.byType(Slider)).first.onChanged!(0);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '#000000',
    );
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();
    expect(renderer.textColor, Colors.black);
  });
  testWidgets('경로는 경고 확인 뒤 선 모양으로 포함하고 다시 제외합니다', (tester) async {
    final renderer = Renderer();
    await show(tester, renderer, settings: true);
    await tester.tap(find.text('경로 포함'));
    await tester.pumpAndSettle();
    expect(find.textContaining('위치를 유추'), findsOneWidget);
    await tester.tap(find.text('포함'));
    await tester.pumpAndSettle();
    expect(renderer.options.last.route!.isEmpty, isFalse);
    await tester.tap(find.text('경로 포함'));
    await tester.pumpAndSettle();
    expect(renderer.options.last.route, isNull);
  });
  testWidgets('공유 중 중복 실행을 막고 팝오버 위치와 취소 결과를 처리합니다', (tester) async {
    final service = ShareService();
    await show(tester, Renderer(), service: service);
    await tester.tap(find.byTooltip('공유'));
    await tester.pump();
    await tester.tap(find.byTooltip('공유'));
    await tester.pump();
    expect(service.calls, 1);
    expect(service.origin!.width, greaterThan(0));
    expect(service.origin!.height, greaterThan(0));
    service.response.complete(RunShareResult.cancelled);
    await tester.pumpAndSettle();
    expect(find.text('공유를 취소했습니다.'), findsOneWidget);
  });
  testWidgets('이미지와 공유창 오류는 재시도 가능하며 성공으로 표시하지 않습니다', (tester) async {
    final renderer = Renderer()..fail = true;
    final service = ShareService()..fail = true;
    await show(tester, renderer, service: service);
    expect(find.text('이미지 다시 만들기'), findsOneWidget);
    renderer.fail = false;
    await tester.tap(find.text('이미지 다시 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('공유'));
    await tester.pumpAndSettle();
    expect(find.textContaining('공유창을 열지 못했습니다'), findsOneWidget);
    expect(find.text('공유 앱으로 전달했습니다.'), findsNothing);
  });
  testWidgets('계정 전환은 이미지를 숨기고 공유를 차단합니다', (tester) async {
    var current = true;
    final changes = StreamController<void>.broadcast();
    addTearDown(changes.close);
    final service = ShareService();
    await show(
      tester,
      Renderer(),
      service: service,
      owner: () => current,
      changes: changes.stream,
    );
    current = false;
    changes.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.byTooltip('공유'), findsNothing);
    expect(service.calls, 0);
  });
  for (final size in [
    const Size(320, 568),
    const Size(430, 932),
    const Size(1024, 768),
  ]) {
    testWidgets('공유 미리보기와 옵션이 화면에 맞습니다 (${size.width})', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final renderer = Renderer();
      await show(tester, renderer);
      final preview = find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == '공유 이미지 미리보기',
      );
      expect(tester.getSize(preview), size);
      expect(
        renderer.height,
        (1080 * size.longestSide / size.shortestSide)
            .clamp(1512.0, 3240.0)
            .roundToDouble(),
      );
      await tester.tap(find.byTooltip('공유 설정'));
      await tester.pumpAndSettle();
      expect(find.text('AI 피드백 포함'), findsNothing);
      await tester.ensureVisible(find.byTooltip('사용자 지정 글자 색'));
      await tester.tap(find.byTooltip('사용자 지정 글자 색'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(3));
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      final photos = Photos();
      photos.photo = await tester.runAsync(
        () async => decodeSharePhoto(await photoBytes()),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await show(tester, renderer, photos: photos, settings: true);
      await tester.tap(find.byTooltip('갤러리 사진 선택'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('사진 배경 덮개'));
      await tester.tap(find.text('사진 배경 덮개'));
      await tester.pumpAndSettle();
      expect(renderer.photoOverlay, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
