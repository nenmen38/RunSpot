import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/settings/data/account_service.dart';
import 'package:runquest/features/settings/settings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAccountService implements AccountService {
  final calls = <String>[];
  Object? failure;

  @override
  bool get isCurrentOwner => true;

  @override
  Future<void> deleteMyAccount() async {
    calls.add('delete');
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signOutLocally() async => calls.add('signOut');
}

Widget settingsApp(FakeAccountService service) => MaterialApp(
  home: SettingsScreen(
    adminBuilder: (_) => const SizedBox(),
    isCurrentOwner: () => true,
    accountService: service,
  ),
);

Future<void> openDialog(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('회원 탈퇴'), 200);
  await tester.tap(find.text('회원 탈퇴'));
  await tester.pumpAndSettle();
}

Finder get deleteButton => find.widgetWithText(FilledButton, '탈퇴');

void main() {
  testWidgets('탈퇴를 직접 입력해야 계정을 지우고 로그아웃합니다', (tester) async {
    final service = FakeAccountService();
    await tester.pumpWidget(settingsApp(service));
    await openDialog(tester);

    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '탈 퇴');
    await tester.pump();
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '탈퇴');
    await tester.pump();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(service.calls, ['delete', 'signOut']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('취소하거나 실패하면 계정을 유지하고 안내합니다', (tester) async {
    final service = FakeAccountService()
      ..failure = const PostgrestException(message: 'network', code: '08006');
    await tester.pumpWidget(settingsApp(service));
    await openDialog(tester);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(service.calls, isEmpty);

    await openDialog(tester);
    await tester.enterText(find.byType(TextField), '탈퇴');
    await tester.pump();
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(service.calls, ['delete']);
    expect(find.text('탈퇴하지 못했습니다. 네트워크를 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
