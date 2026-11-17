import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:runquest/features/chat/chat_draft_store.dart';
import 'package:runquest/features/chat/friend_chat_content.dart';

void main() {
  test('앱 재실행 후 같은 계정과 대화에서만 전송 대기를 복구합니다', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('runspot-chat-');
    addTearDown(() => dir.delete(recursive: true));
    ChatDraftStore store(String owner, String peer) => ChatDraftStore(
      owner: owner,
      namespace: 'server',
      peer: peer,
      factory: databaseFactoryFfi,
      databasePath: () async => '${dir.path}/drafts.sqlite',
    );
    await store(
      'a',
      'b',
    ).save(const FriendChatDraft(id: 'request', body: '재시도', replyTo: 7));
    expect((await store('a', 'b').read())!.replyTo, 7);
    expect(await store('b', 'a').read(), isNull);
    expect(await store('a', 'c').read(), isNull);
    await store('a', 'b').remove('different');
    expect(await store('a', 'b').read(), isNotNull);
    await store('a', 'b').remove('request');
    expect(await store('a', 'b').read(), isNull);
  });
}
