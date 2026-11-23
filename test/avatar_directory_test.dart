import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:runquest/features/chat/chat_room_style.dart';
import 'package:runquest/features/profile/reportable_avatar_header.dart';
import 'package:runquest/shared/data/account_rpc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

class _ReportApi implements AccountRpc {
  _ReportApi(this.current);
  Map<String, dynamic> current;
  Map<String, dynamic>? submitted;
  @override
  String get owner => 'reporter';
  @override
  SupabaseClient get client =>
      throw UnsupportedError('테스트에서는 원격 연결을 사용하지 않습니다.');
  @override
  Future<dynamic> call(String method, Map<String, dynamic> params) async {
    if (method == 'reportable_avatar') return current;
    if (method == 'report_avatar') {
      submitted = params;
      return null;
    }
    throw UnsupportedError(method);
  }
}

void main() {
  final photo = img.encodeJpg(img.Image(width: 8, height: 8));
  tearDown(AvatarDirectory.instance.unbind);

  testWidgets('프로필 사진이 바뀌어도 신고 창을 열 때 본 사진과 분류를 전송합니다', (tester) async {
    final original = base64Encode(photo);
    final api = _ReportApi({'version': '처음', 'photo': original});
    AvatarDirectory.instance.bind(_Source(photo), reports: api);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReportableAvatarHeader(
            userId: 'friend',
            nickname: '친구',
            size: 56,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('프로필 사진 신고'));
    await tester.pumpAndSettle();
    api.current = {
      'version': '나중',
      'photo': base64Encode(img.encodeJpg(img.Image(width: 5, height: 5))),
    };
    final preview = tester.widget<Image>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Image),
      ),
    );
    expect((preview.image as MemoryImage).bytes, photo);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('개인정보 노출').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '신고'));
    await tester.pumpAndSettle();
    expect(api.submitted, {
      'target': 'friend',
      'version_id': '처음',
      'jpeg': original,
      'reason': '개인정보 노출',
    });
    expect(find.text('프로필 사진 신고가 접수되었습니다.'), findsOneWidget);
  });

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

  test('서버가 줄바꿈을 넣어 보낸 사진(base64)도 풉니다', () {
    // PostgreSQL encode(...,'base64')는 76글자마다 줄바꿈을 넣습니다.
    final encoded = base64Encode(photo);
    final wrapped = [
      for (var i = 0; i < encoded.length; i += 76)
        encoded.substring(i, (i + 76).clamp(0, encoded.length)),
    ].join('\n');
    expect(wrapped, contains('\n'));
    expect(decodeAvatarBase64(wrapped), photo);
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
