import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:runquest/features/auth/data/nickname_service.dart';
import 'package:runquest/features/auth/nickname.dart';
import 'package:runquest/features/profile/data/profile_avatar_service.dart';

class _Nicknames implements NicknameService {
  @override
  Future<NicknameState> load() async =>
      const NicknameState(verified: true, nickname: '바람러너');
  @override
  Future<void> save(String nickname) async {}
}

class _Avatars implements ProfileAvatarService {
  Uint8List? photo;
  final saved = <Uint8List>[];
  var removed = 0;
  @override
  Future<Uint8List?> load() async => photo;
  @override
  Future<void> save(Uint8List jpeg) async {
    saved.add(jpeg);
    photo = jpeg;
  }

  @override
  Future<void> remove() async {
    removed++;
    photo = null;
  }
}

void main() {
  test('고른 사진은 가운데를 정사각형으로 잘라 줄입니다', () {
    final wide = img.Image(width: 1200, height: 600);
    final jpeg = squareProfilePhoto(img.encodeJpg(wide));
    final result = img.decodeJpg(jpeg)!;
    expect((result.width, result.height), (400, 400));
    expect(jpeg.length, lessThanOrEqualTo(300 * 1024));
    expect(
      () => squareProfilePhoto(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<ProfilePhotoException>()),
    );
  });

  testWidgets('프로필 편집에서 닉네임과 함께 사진을 고르고 기본 이미지로 되돌립니다', (tester) async {
    final avatars = _Avatars();
    final picked = squareProfilePhoto(
      img.encodeJpg(img.Image(width: 50, height: 50)),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NicknameScreen(
          service: _Nicknames(),
          avatarService: avatars,
          pickPhoto: () async => picked,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('프로필 편집'), findsOneWidget);
    expect(find.text('닉네임 저장'), findsOneWidget);
    // 사진이 없으면 닉네임 첫 글자를 보여줍니다.
    expect(find.text('바'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-photo')));
    await tester.pumpAndSettle();
    expect(find.text('기본 이미지로 변경'), findsNothing);
    await tester.tap(find.text('앨범에서 사진 선택'));
    await tester.pumpAndSettle();
    expect(avatars.saved.single, picked);
    expect(find.text('프로필 사진을 바꿨어요.'), findsOneWidget);
    expect(find.text('바'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('profile-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기본 이미지로 변경'));
    await tester.pumpAndSettle();
    expect(avatars.removed, 1);
    expect(find.text('바'), findsOneWidget);
  });

  testWidgets('닉네임만 정할 때(가입 직후)는 사진 편집을 보여주지 않습니다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NicknameScreen(service: _Nicknames())),
    );
    await tester.pumpAndSettle();
    expect(find.text('닉네임'), findsWidgets);
    expect(find.byKey(const ValueKey('profile-photo')), findsNothing);
  });
}
