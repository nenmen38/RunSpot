import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/shared/errors/server_error.dart';
import 'package:runquest/shared/network/network_status.dart';
import 'package:runquest/shared/network/offline_banner.dart';
import 'package:runquest/shared/widgets/status_view.dart';

void main() {
  final status = NetworkStatus.instance;
  tearDown(() => status.setOnline(true));

  testWidgets('인터넷이 끊기면 맨 위에 띠가 나오고 다시 연결되면 잠깐 알려 줍니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OfflineBanner(
          child: Scaffold(body: Center(child: Text('내용'))),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('offline-banner')), findsNothing);

    status.setOnline(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('offline-banner')), findsOneWidget);
    expect(find.textContaining('오프라인이에요'), findsOneWidget);
    // 띠가 화면을 가리지 않고 내용을 아래로 내립니다.
    final banner = tester.getRect(find.byKey(const ValueKey('offline-banner')));
    expect(tester.getRect(find.byType(Scaffold)).top, banner.bottom);

    status.setOnline(true);
    await tester.pump();
    expect(find.text('다시 연결됐어요'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('다시 연결됐어요'), findsNothing);
    expect(find.byKey(const ValueKey('online-banner')), findsNothing);
  });

  testWidgets('오류 화면은 오프라인이면 같은 안내를 보이고 연결되면 다시 불러옵니다', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusView.error(
            message: '채팅을 불러오지 못했어요.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('채팅을 불러오지 못했어요.'), findsOneWidget);

    status.setOnline(false);
    await tester.pump();
    expect(find.text(offlineMessage), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(retries, 0);

    status.setOnline(true);
    await tester.pump();
    expect(retries, 1);
    expect(find.text('채팅을 불러오지 못했어요.'), findsOneWidget);
  });

  testWidgets('좁은 자리의 오류도 오프라인 문구로 바뀝니다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InlineError(message: '불러오지 못했습니다.')),
      ),
    );
    status.setOnline(false);
    await tester.pump();
    expect(find.text('인터넷에 연결되어 있지 않아요.'), findsOneWidget);
  });

  test('연결 실패 오류는 인터넷 확인 문구를 덧붙입니다', () {
    expect(isNetworkError(const SocketException('끊김')), isTrue);
    expect(isNetworkError(StateError('다른 오류')), isFalse);
    expect(
      unexpectedServerError(const SocketException('끊김'), '글을 불러오지 못했어요.'),
      '글을 불러오지 못했어요. 인터넷 연결을 확인해 주세요.',
    );
    expect(unexpectedServerError(StateError('x'), '실패'), '실패');
  });
}
