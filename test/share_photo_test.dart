import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:runquest/features/run_share/data/share_photo_service.dart';

class Picker extends ImagePicker {
  XFile? file;
  PlatformException? error;
  ImageSource? source;
  bool? metadata;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    metadata = requestFullMetadata;
    if (error != null) throw error!;
    return file;
  }
}

Future<Uint8List> photoBytes({int width = 40, int height = 30}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.red, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  testWidgets('앱 재시작 시 중단된 사진을 다른 기록에 자동 적용하지 않습니다', (tester) async {
    var calls = 0;
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'retrieve');
      calls++;
      return {'type': 'image', 'path': '/기록에자동연결하지않을사진.jpg'};
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await discardInterruptedSharePhoto();
    expect(calls, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets('사진 한 장만 선택하며 전체 메타데이터나 카메라를 요청하지 않습니다', (tester) async {
    await tester.runAsync(() async {
      final picker = Picker()..file = XFile.fromData(await photoBytes());
      final image = await GallerySharePhotoService(picker: picker).pick();
      expect(picker.source, ImageSource.gallery);
      expect(picker.metadata, isFalse);
      expect(image!.width, 40);
      image.dispose();
      picker.file = null;
      expect(await GallerySharePhotoService(picker: picker).pick(), isNull);
      picker.error = PlatformException(code: 'photo_access_denied');
      await expectLater(
        GallerySharePhotoService(picker: picker).pick(),
        throwsA(isA<SharePhotoException>()),
      );
    });
  });
  testWidgets('큰 사진은 비율을 유지해 축소하고 잘못된 사진은 거절합니다', (tester) async {
    await tester.runAsync(() async {
      final image = await decodeSharePhoto(
        await photoBytes(width: 3000, height: 1500),
      );
      expect(image.width, 2048);
      expect(image.height, 1024);
      image.dispose();
      await expectLater(
        decodeSharePhoto(Uint8List(0)),
        throwsA(isA<SharePhotoException>()),
      );
      await expectLater(
        decodeSharePhoto(Uint8List(21 * 1024 * 1024)),
        throwsA(isA<SharePhotoException>()),
      );
      await expectLater(
        decodeSharePhoto(Uint8List.fromList([1, 2, 3])),
        throwsException,
      );
    });
  });
}
