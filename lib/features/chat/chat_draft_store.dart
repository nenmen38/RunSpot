import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'friend_chat_content.dart';

/// 전송 요청 식별자를 포함해 보관하여 응답 유실 후 재시도에도 중복 전송하지 않습니다.
class ChatDraftStore {
  ChatDraftStore({
    required this.owner,
    required this.namespace,
    required this.peer,
    DatabaseFactory? factory,
    Future<String> Function()? databasePath,
  }) : _factory = factory ?? databaseFactory,
       _path = databasePath;
  final String owner;
  final String namespace;
  final String peer;
  final DatabaseFactory _factory;
  final Future<String> Function()? _path;

  Future<T> _withDatabase<T>(Future<T> Function(Database) action) async {
    final location = _path != null
        ? await _path()
        : path.join(
            (await getApplicationSupportDirectory()).path,
            'chat_drafts.sqlite',
          );
    final db = await _factory.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA synchronous = FULL'),
        onCreate: (db, _) => db.execute('''
        CREATE TABLE drafts(
          namespace TEXT NOT NULL, owner TEXT NOT NULL, peer TEXT NOT NULL,
          request_id TEXT NOT NULL, content TEXT NOT NULL,
          PRIMARY KEY(namespace,owner,peer)
        )
      '''),
      ),
    );
    // 공용 연결의 수명은 sqflite가 관리합니다. 다른 대화가 쓰는 동안 닫지 않습니다.
    return action(db);
  }

  Future<FriendChatDraft?> read() => _withDatabase((db) async {
    final rows = await db.query(
      'drafts',
      where: 'namespace=? AND owner=? AND peer=?',
      whereArgs: [namespace, owner, peer],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final data = jsonDecode(rows.single['content'] as String) as Map;
    return FriendChatDraft(
      id: rows.single['request_id'] as String,
      body: data['body'] as String?,
      replyTo: data['reply_to'] as int?,
      photo: data['photo'] as String?,
      runId: data['run_id'] as String?,
    );
  });

  Future<void> save(FriendChatDraft draft) => _withDatabase((db) async {
    await db.insert('drafts', {
      'namespace': namespace,
      'owner': owner,
      'peer': peer,
      'request_id': draft.id,
      'content': jsonEncode({
        'body': draft.body,
        'reply_to': draft.replyTo,
        'photo': draft.photo,
        'run_id': draft.runId,
      }),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  });

  Future<void> remove(String id) => _withDatabase((db) async {
    await db.delete(
      'drafts',
      where: 'namespace=? AND owner=? AND peer=? AND request_id=?',
      whereArgs: [namespace, owner, peer, id],
    );
  });

  Future<void> clearAccount() => _withDatabase((db) async {
    await db.delete(
      'drafts',
      where: 'namespace=? AND owner=?',
      whereArgs: [namespace, owner],
    );
  });
}
