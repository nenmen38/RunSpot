import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/board/races/marathon_board.dart';
import 'package:runquest/features/board/races/marathon_detail_screen.dart';
import 'package:runquest/features/board/races/marathon_status_badge.dart';
import 'package:runquest/features/board/races/marathon_event.dart';
import 'package:runquest/features/board/races/marathon_service.dart';

MarathonEvent event(String status, String name) => MarathonEvent.fromJson({
  'id': status,
  'status': status,
  'data': {
    'name': name,
    'event': {'startDate': '2027-03-21'},
    'location': {'region': '서울', 'venue': '광화문'},
    'registration': {
      'price': {'10KM': 50000},
      'site': 'https://example.com',
    },
  },
});

class FakeMarathons implements MarathonService {
  int calls = 0;
  bool fail = false;
  @override
  Future<MarathonFeed> load() async {
    calls++;
    if (fail) throw Exception('오류');
    return MarathonFeed([
      event('upcoming', '봄 대회'),
      event('open', '서울 대회'),
      event('closed', '마감 대회'),
      event('unknown', '미정 대회'),
    ], DateTime.now().toUtc());
  }
}

void main() {
  test('공식 사이트는 안전한 https 링크만 표시합니다', () {
    final item = event('open', '서울 대회');
    expect(item.website.toString(), 'https://example.com');
    final data = Map<String, dynamic>.from(item.data);
    data['registration'] = {'site': 'javascript:alert(1)'};
    expect(
      MarathonEvent.fromJson({'id': 'test', 'status': 'unknown', 'data': data})
          .website,
      isNull,
    );
    expect(item.registrationPeriod, isNull);
    expect(item.matches('광화문'), isTrue);
  });

  testWidgets('접수 상태별 필터와 상세 정보를 표시합니다', (tester) async {
    final service = FakeMarathons();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarathonBoard(
            service: service,
            notices: const [],
            onOpenNotice: (_) {},
            refreshNotices: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('봄 대회'), findsOneWidget);
    expect(find.text('서울 대회'), findsOneWidget);
    await tester.tap(find.byTooltip('접수 상태 선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '접수 중'));
    await tester.pumpAndSettle();
    expect(find.text('봄 대회'), findsNothing);
    expect(find.text('서울 대회'), findsOneWidget);
    await tester.tap(find.text('서울 대회'));
    await tester.pumpAndSettle();
    expect(find.text('50,000원'), findsOneWidget);
    expect(find.text('공식 사이트'), findsOneWidget);
    expect(find.text('접수'), findsOneWidget);
    expect(find.text('미정'), findsOneWidget);
    expect(service.calls, 1);
  });

  testWidgets('실패 후 재시도와 검색 결과를 표시합니다', (tester) async {
    final service = FakeMarathons()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarathonBoard(
            service: service,
            query: '서울 대회',
            notices: const [],
            onOpenNotice: (_) {},
            refreshNotices: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('대회 정보를 불러오지 못했어요.'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('서울 대회'), findsOneWidget);
    expect(find.text('봄 대회'), findsNothing);
    expect(service.calls, 2);
  });

  testWidgets('작은 화면의 두 배 글자에서도 필터와 상세를 사용할 수 있습니다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Widget large(Widget child) => MaterialApp(
      builder: (context, page) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: page!,
      ),
      home: child,
    );
    await tester.pumpWidget(
      large(
        Scaffold(
          body: MarathonBoard(
            service: FakeMarathons(),
            notices: const [],
            onOpenNotice: (_) {},
            refreshNotices: () async {},
            onSearch: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('접수 상태 선택'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<String>, '접수 미정'), findsOneWidget);
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '접수 미정'));
    await tester.pumpAndSettle();
    expect(find.text('미정 대회'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      large(MarathonDetailScreen(event: event('open', '서울 국제 마라톤 대회'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('공식 사이트'), findsOneWidget);
    expect(
      tester.getSize(find.byType(FilledButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('접수 배지의 글자 대비는 모든 상태에서 4.5 이상입니다', (tester) async {
    for (final status in MarathonStatus.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MarathonStatusBadge(status: status)),
        ),
      );
      final badge = find.byType(MarathonStatusBadge);
      final text = tester.widget<Text>(
        find.descendant(of: badge, matching: find.byType(Text)),
      );
      final box = tester.widget<Container>(
        find.descendant(of: badge, matching: find.byType(Container)),
      );
      final background = (box.decoration! as BoxDecoration).color!;
      final a = text.style!.color!.computeLuminance();
      final b = background.computeLuminance();
      final ratio = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: status.label);
    }
  });
}
