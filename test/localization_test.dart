import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/widgets/run_completion_screen.dart';
import 'package:runquest/features/run_history/models/run_record.dart';
import 'package:runquest/features/run_history/models/run_route.dart';
import 'package:runquest/features/run_share/models/share_route.dart';
import 'package:runquest/features/settings/appearance/app_appearance.dart';
import 'package:runquest/l10n/l10n.dart';
import 'package:runquest/shared/network/network_status.dart';
import 'package:runquest/shared/network/offline_banner.dart';

class _MemoryStore implements AppearanceStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final record = RunRecord(
  id: 'run',
  clientRunId: 'client',
  startedAt: DateTime.utc(2026),
  endedAt: DateTime.utc(2026, 1, 1, 1),
  distanceMeters: 5000,
  durationSeconds: 1500,
);

Widget localized(Locale locale, Widget home) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Widget completion() => RunCompletionScreen(
  record: record,
  route: ShareRoute.shape(const RunRoute.empty()),
  isCurrentOwner: () => true,
);

void main() {
  test('고른 언어를 저장하고 다시 불러옵니다', () async {
    final store = _MemoryStore();
    final first = AppAppearance(store: store);
    await first.setLanguage(AppLanguage.english);
    final second = AppAppearance(store: store);
    await second.load();
    expect(second.language, AppLanguage.english);
    expect(second.language.locale, const Locale('en'));
    expect(AppLanguage.system.locale, isNull);
  });

  testWidgets('영어를 고르면 러닝 완료 화면이 영어로 보입니다', (tester) async {
    await tester.pumpWidget(localized(const Locale('en'), completion()));
    await tester.pumpAndSettle();
    expect(find.text('Run complete'), findsOneWidget);
    expect(find.text('Create share card'), findsOneWidget);
    expect(find.text('My runs'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('한국어(또는 번역 설정이 없는 곳)에서는 한국어로 보입니다', (tester) async {
    await tester.pumpWidget(localized(const Locale('ko'), completion()));
    await tester.pumpAndSettle();
    expect(find.text('러닝 완료'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: completion()));
    await tester.pumpAndSettle();
    expect(find.text('공유 카드 만들기'), findsOneWidget);
  });

  testWidgets('오프라인 띠도 언어를 따릅니다', (tester) async {
    addTearDown(() => NetworkStatus.instance.setOnline(true));
    await tester.pumpWidget(
      localized(
        const Locale('en'),
        const OfflineBanner(child: Scaffold(body: SizedBox())),
      ),
    );
    NetworkStatus.instance.setOnline(false);
    await tester.pumpAndSettle();
    expect(find.textContaining("You're offline"), findsOneWidget);
  });
}
