import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 프로필 사진을 불러오고 바꿉니다. 사진은 정사각형 JPEG로 저장합니다.
abstract interface class ProfileAvatarService {
  /// 내 프로필 사진입니다. 없으면 null입니다.
  Future<Uint8List?> load();
  Future<void> save(Uint8List jpeg);
  Future<void> remove();
}

class SupabaseProfileAvatarService implements ProfileAvatarService {
  SupabaseProfileAvatarService(this.client);
  final SupabaseClient client;

  @override
  Future<Uint8List?> load() async {
    final owner = client.auth.currentUser?.id;
    if (owner == null) return null;
    final value = await client.rpc('user_avatar', params: {'target': owner});
    return value is String && value.isNotEmpty
        ? decodeAvatarBase64(value)
        : null;
  }

  // 목록에서 쓸 작은 사진(120×120)을 함께 올려 다른 화면의 데이터 사용량을 줄입니다.
  @override
  Future<void> save(Uint8List jpeg) async {
    final thumb = await compute(profileThumbnail, jpeg);
    await client.rpc(
      'set_my_avatar',
      params: {'jpeg': base64Encode(jpeg), 'thumb': base64Encode(thumb)},
    );
  }

  @override
  Future<void> remove() => client.rpc('remove_my_avatar');
}

/// 서버(PostgreSQL)가 보내는 base64에는 76글자마다 줄바꿈이 들어 있어 지운 뒤 풉니다.
/// 줄바꿈을 지우지 않으면 풀기에 실패해 저장한 사진이 화면에 보이지 않습니다.
Uint8List decodeAvatarBase64(String value) =>
    base64Decode(value.replaceAll(RegExp(r'\s'), ''));

class ProfilePhotoException implements Exception {
  const ProfilePhotoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 갤러리에서 사진을 골라 가운데를 정사각형으로 잘라 줄입니다. 고르지 않으면 null입니다.
Future<Uint8List?> pickProfilePhoto() async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 92,
      requestFullMetadata: false,
    );
  } catch (_) {
    throw const ProfilePhotoException('사진을 불러올 수 없어요. 사진 접근 권한을 확인해 주세요.');
  }
  if (file == null) return null;
  if (await file.length() > 20 * 1024 * 1024) {
    throw const ProfilePhotoException('20MB 이하의 사진을 선택해 주세요.');
  }
  return compute(squareProfilePhoto, await file.readAsBytes());
}

/// 사진 가운데를 정사각형으로 잘라 400×400 JPEG(300KB 이하)로 만듭니다.
Uint8List squareProfilePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const ProfilePhotoException('사진을 읽을 수 없어요. 다른 사진을 선택해 주세요.');
  }
  final square = img.copyResizeCropSquare(
    img.bakeOrientation(decoded),
    size: 400,
  );
  for (final quality in [86, 76, 64, 50]) {
    final jpeg = img.encodeJpg(square, quality: quality);
    if (jpeg.length <= 300 * 1024) return jpeg;
  }
  throw const ProfilePhotoException('사진을 줄이지 못했어요. 다른 사진을 선택해 주세요.');
}

/// 목록·채팅에 쓰는 120×120 작은 사진(40KB 이하)입니다.
Uint8List profileThumbnail(Uint8List jpeg) {
  final decoded = img.decodeImage(jpeg);
  if (decoded == null) {
    throw const ProfilePhotoException('사진을 읽을 수 없어요. 다른 사진을 선택해 주세요.');
  }
  final small = img.copyResizeCropSquare(decoded, size: 120);
  for (final quality in [82, 68, 50]) {
    final thumb = img.encodeJpg(small, quality: quality);
    if (thumb.length <= 40 * 1024) return thumb;
  }
  throw const ProfilePhotoException('사진을 줄이지 못했어요. 다른 사진을 선택해 주세요.');
}
