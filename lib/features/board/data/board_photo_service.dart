import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class BoardPhotoException implements Exception {
  const BoardPhotoException(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract interface class BoardPhotoService {
  /// 최대 [limit]장을 골라 위치 등 메타데이터가 없는 JPEG로 반환합니다.
  Future<List<Uint8List>> pick(int limit);
}

class GalleryBoardPhotoService implements BoardPhotoService {
  GalleryBoardPhotoService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<List<Uint8List>> pick(int limit) async {
    if (limit <= 0) return const [];
    try {
      final files = await _picker.pickMultiImage(
        limit: limit < 2 ? null : limit,
        maxWidth: boardPhotoMaxSide.toDouble(),
        maxHeight: boardPhotoMaxSide.toDouble(),
        imageQuality: 90,
        requestFullMetadata: false,
      );
      final photos = <Uint8List>[];
      for (final file in files.take(limit)) {
        if (await file.length() > 20 * 1024 * 1024) {
          throw const BoardPhotoException('20MB 이하의 사진을 선택해 주세요.');
        }
        photos.add(await encodeBoardPhoto(await file.readAsBytes()));
      }
      return photos;
    } on PlatformException catch (error) {
      if (error.code == 'photo_access_denied' ||
          error.code == 'photo_access_restricted') {
        throw const BoardPhotoException(
          '사진을 선택할 수 없습니다. 기기 설정에서 사진 접근 권한을 확인해 주세요.',
        );
      }
      throw const BoardPhotoException('사진을 불러오지 못했습니다. 다른 사진을 선택해 주세요.');
    }
  }
}

const boardPhotoMaxSide = 1600;
const boardPhotoMaxBytes = 3 * 1024 * 1024;

/// 사진을 다시 그려 JPEG로 저장합니다. 원본의 촬영 위치(EXIF GPS)와 기기 정보는 복사하지 않습니다.
Future<Uint8List> encodeBoardPhoto(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
    throw const BoardPhotoException('20MB 이하의 사진을 선택해 주세요.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
    } catch (_) {
      throw const BoardPhotoException('사진 형식을 읽을 수 없습니다. 다른 사진을 선택해 주세요.');
    }
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width * descriptor.height > 100000000) {
      throw const BoardPhotoException('사진 해상도가 너무 큽니다. 작은 사진을 선택해 주세요.');
    }
    final longest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = longest > boardPhotoMaxSide
        ? boardPhotoMaxSide / longest
        : 1.0;
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round().clamp(
        1,
        boardPhotoMaxSide,
      ),
      targetHeight: (descriptor.height * scale).round().clamp(
        1,
        boardPhotoMaxSide,
      ),
    );
    image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) {
      throw const BoardPhotoException('사진을 불러오지 못했습니다. 다른 사진을 선택해 주세요.');
    }
    // 화면이 멈추지 않도록 JPEG 압축은 별도 실행 공간에서 처리합니다.
    final jpeg = await compute(_encodeJpeg, (
      width: image.width,
      height: image.height,
      rgba: rgba.buffer.asUint8List(),
    ));
    if (jpeg.length > boardPhotoMaxBytes) {
      throw const BoardPhotoException('사진 용량이 너무 큽니다. 다른 사진을 선택해 주세요.');
    }
    return jpeg;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Uint8List _encodeJpeg(({int width, int height, Uint8List rgba}) raw) =>
    img.encodeJpg(
      img.Image.fromBytes(
        width: raw.width,
        height: raw.height,
        bytes: raw.rgba.buffer,
        numChannels: 4,
      ),
      quality: 82,
    );
