import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:runquest/features/auth/data/nickname_service.dart';
import 'package:runquest/features/auth/nickname.dart';
import 'package:runquest/features/profile/data/profile_avatar_service.dart';

class _Nicknames implements NicknameService {
  final saved = <String>[];
  @override
  Future<NicknameState> load() async =>
      const NicknameState(verified: true, nickname: '바람러너');
  @override
  Future<void> save(String nickname) async => saved.add(nickname);
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

  testWidgets('사진과 닉네임을 바꾼 뒤 변경사항 저장 한 번으로 함께 저장합니다', (tester) async {
    final avatars = _Avatars();
    final nicknames = _Nicknames();
    final picked = squareProfilePhoto(
      img.encodeJpg(img.Image(width: 50, height: 50)),
    );
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => NicknameScreen(
                      service: nicknames,
                      avatarService: avatars,
                      pickPhoto: () async => picked,
                    ),
                  ),
                ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('프로필 편집'), findsOneWidget);
    FilledButton save() =>
        tester.widget(find.widgetWithText(FilledButton, '변경사항 저장'));
    // 아무것도 바꾸지 않으면 저장할 수 없습니다. 사진이 없으면 닉네임 첫 글자를 보여줍니다.
    expect(save().onPressed, isNull);
    expect(find.text('바'), findsOneWidget);

    // 사진을 고르면 화면에만 먼저 보이고 아직 저장하지 않습니다.
    await tester.tap(find.byKey(const ValueKey('profile-photo')));
    await tester.pumpAndSettle();
    expect(find.text('기본 이미지로 변경'), findsNothing);
    await tester.tap(find.text('앨범에서 사진 선택'));
    await tester.pumpAndSettle();
    expect(avatars.saved, isEmpty);
    expect(find.text('바'), findsNothing);
    expect(find.text('아래 변경사항 저장을 눌러야 사진이 바뀌어요.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '새벽러너');
    await tester.pump();
    await tester.tap(find.text('변경사항 저장'));
    await tester.pumpAndSettle();
    expect(avatars.saved.single, picked);
    expect(nicknames.saved, ['새벽러너']);
    expect(result, isTrue);
  });

  testWidgets('기본 이미지로 바꾸고 저장하면 사진을 지웁니다', (tester) async {
    final avatars = _Avatars()
      ..photo = squareProfilePhoto(
        img.encodeJpg(img.Image(width: 50, height: 50)),
      );
    final nicknames = _Nicknames();
    await tester.pumpWidget(
      MaterialApp(
        home: NicknameScreen(service: nicknames, avatarService: avatars),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기본 이미지로 변경'));
    await tester.pumpAndSettle();
    expect(avatars.removed, 0);
    expect(find.text('바'), findsOneWidget);
    await tester.tap(find.text('변경사항 저장'));
    await tester.pumpAndSettle();
    expect(avatars.removed, 1);
    // 닉네임은 그대로라 저장하지 않습니다.
    expect(nicknames.saved, isEmpty);
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
