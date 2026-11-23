import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:runquest/features/chat/chat_room_style.dart';
import 'package:runquest/features/profile/avatar_directory.dart';
import 'package:runquest/features/profile/data/profile_avatar_service.dart';

class _Source implements AvatarSource {
  _Source(this.photo);
  final Uint8List photo;
  final calls = <(List<String>, List<String>, List<String>)>[];
  @override
  bool get isCurrentOwner => true;
  @override
  Future<
    ({
      Map<String, Uint8List> users,
      Map<String, Uint8List> posts,
      Map<String, Uint8List> comments,
    })
  >
  load({
    List<String> users = const [],
    List<String> posts = const [],
    List<String> comments = const [],
  }) async {
    calls.add((users, posts, comments));
    return (
      users: {
        for (final id in users)
          if (id == 'friend') id: photo,
      },
      posts: {for (final id in posts) id: photo},
      comments: <String, Uint8List>{},
    );
  }
}

void main() {
  final photo = img.encodeJpg(img.Image(width: 8, height: 8));
  tearDown(AvatarDirectory.instance.unbind);

  testWidgets('화면의 여러 얼굴을 한 번에 불러와 사진이 있는 사람만 사진으로 바꿉니다', (tester) async {
    final source = _Source(photo);
    AvatarDirectory.instance.bind(source);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatAvatar(nickname: '바람', userId: 'friend'),
              ChatAvatar(nickname: '새벽', userId: 'stranger'),
              UserAvatar(nickname: '글쓴이', postId: 'post-1'),
              ChatAvatar(nickname: '바람', userId: 'friend'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // 같은 사람은 한 번만, 종류가 달라도 한 번의 요청으로 묻습니다.
    expect(source.calls, hasLength(1));
    expect(source.calls.single.$1.toSet(), {'friend', 'stranger'});
    expect(source.calls.single.$2, ['post-1']);
    final avatars = tester
        .widgetList<CircleAvatar>(find.byType(CircleAvatar))
        .toList();
    expect(avatars.where((a) => a.foregroundImage != null), hasLength(3));
    // 사진이 없는 사람은 닉네임 첫 글자를 보여줍니다.
    expect(find.text('새'), findsOneWidget);
  });

  testWidgets('내 사진을 바꾸면 모든 화면의 내 얼굴이 바로 바뀝니다', (tester) async {
    AvatarDirectory.instance.bind(_Source(photo));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatAvatar(nickname: '나', userId: 'me'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('나'), findsOneWidget);
    AvatarDirectory.instance.updateMine('me', photo);
    await tester.pump();
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).foregroundImage,
      isNotNull,
    );
  });

  test('목록용 작은 사진은 120×120으로 줄입니다', () {
    final thumb = profileThumbnail(
      img.encodeJpg(img.Image(width: 400, height: 400)),
    );
    final decoded = img.decodeJpg(thumb)!;
    expect((decoded.width, decoded.height), (120, 120));
    expect(thumb.length, lessThanOrEqualTo(40 * 1024));
  });
}
