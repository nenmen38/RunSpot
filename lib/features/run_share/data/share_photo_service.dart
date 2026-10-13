import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class SharePhotoException implements Exception {
  const SharePhotoException(this.message);
  final String message;
}

abstract interface class SharePhotoService {
  Future<ui.Image?> pick();
}

class GallerySharePhotoService implements SharePhotoService {
  GallerySharePhotoService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<ui.Image?> pick() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      if (await file.length() > 20 * 1024 * 1024) {
        throw const SharePhotoException('20MB 이하의 사진을 선택해 주세요.');
      }
      return await decodeSharePhoto(await file.readAsBytes());
    } on PlatformException catch (error) {
      if (error.code == 'photo_access_denied' ||
          error.code == 'photo_access_restricted') {
        throw const SharePhotoException(
          '사진을 선택할 수 없습니다. 기기 설정에서 사진 접근 권한을 확인해 주세요.',
        );
      }
      throw const SharePhotoException('사진을 불러오지 못했습니다. 다른 사진을 선택해 주세요.');
    }
  }
}

Future<ui.Image> decodeSharePhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const SharePhotoException('20MB 이하의 사진을 선택해 주세요.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width * descriptor.height > 100000000) {
      throw const SharePhotoException('사진 해상도가 너무 큽니다. 작은 사진을 선택해 주세요.');
    }
    // 데스크톱 선택기의 축소 옵션 미지원도 고려해 실제 디코딩 크기를 제한합니다.
    final scale =
        2048 /
        (descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height);
    codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1
          ? (descriptor.width * scale).round().clamp(1, 2048)
          : null,
      targetHeight: scale < 1
          ? (descriptor.height * scale).round().clamp(1, 2048)
          : null,
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<void> discardInterruptedSharePhoto() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    // 앱 종료 전에 고른 사진을 다른 계정·기록에 자동 연결하지 않습니다.
    // 원본 파일은 삭제하지 않고 선택기의 복구 대기 상태만 비웁니다.
    await ImagePicker().retrieveLostData();
  } on PlatformException {
    // 선택기 오류는 앱 시작이나 러닝 측정을 막지 않습니다.
  }
}
