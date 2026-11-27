import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/character/character_background.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/profile/profile_sections.dart';
import 'package:runquest/features/profile/widgets/weekly_quest_panel.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';

import 'support/wallet_fakes.dart';

class _MemoryStore implements AppearanceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test('구역 펼침 상태가 저장되고 다시 읽힌다', () async {
    final store = _MemoryStore();
    final a = ProfileSections(store: store);
    expect(a.isOpen(ProfileSection.card), isTrue);
    await a.toggle(ProfileSection.card);
    expect(a.isOpen(ProfileSection.card), isFalse);
    expect(a.isOpen(ProfileSection.quest), isTrue);
    final b = ProfileSections(store: store);
    await b.load();
    expect(b.isOpen(ProfileSection.card), isFalse);
    await b.toggle(ProfileSection.card);
    expect(b.isOpen(ProfileSection.card), isTrue);
  });

  testWidgets('이번 주 퀘스트를 접으면 항목이 사라지고 요약은 남는다', (tester) async {
    final wallet = WalletController(
      FakeWalletService()
        ..weeklyQuests.add(
          const WeeklyCoinQuest(progress: 2, reward: 20, awarded: false),
        ),
    );
    await wallet.refresh();
    final sections = ProfileSections(store: _MemoryStore());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklyQuestPanel(controller: wallet, sections: sections),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('toggle-quest')));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('이번 주 퀘스트'), findsOneWidget);
    expect(find.byTooltip('이번 주 퀘스트 펼치기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toggle-quest')));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    wallet.dispose();
  });

  group('배경 사진 보관함', () {
    late Directory dir;
    late _MemoryStore store;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('bg_test');
      store = _MemoryStore();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    CharacterBackground make() =>
        CharacterBackground(store: store, directory: () async => dir);

    test('선택·삭제와 저장된 선택 복원', () async {
      final bg = make();
      await bg.load();
      expect(bg.provider, isNull);
      File('${dir.path}/a.jpg').writeAsBytesSync([1]);
      File('${dir.path}/b.jpg').writeAsBytesSync([2]);
      await bg.load();
      expect(bg.names.length, 2);
      await bg.select('a.jpg');
      expect(bg.provider, isNotNull);
      final again = make();
      await again.load();
      expect(again.selected, 'a.jpg');
      await again.remove('a.jpg');
      expect(again.selected, isNull);
      expect(File('${dir.path}/a.jpg').existsSync(), isFalse);
      expect(again.names, ['b.jpg']);
      await again.select(null);
      expect(again.provider, isNull);
    });

    testWidgets('보관함 시트에서 사진을 고르고 기본 트랙으로 돌아간다', (tester) async {
      File('${dir.path}/a.jpg').writeAsBytesSync([1]);
      final bg = make();
      await tester.runAsync(bg.load);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CharacterBackgroundButton(background: bg)),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('character-background-button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('배경 사진'), findsOneWidget);
      expect(find.byKey(const ValueKey('background-add')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('background-a.jpg')));
      await tester.pump();
      expect(bg.selected, 'a.jpg');
      await tester.tap(find.byKey(const ValueKey('background-default')));
      await tester.pump();
      expect(bg.selected, isNull);
    });
  });
}
