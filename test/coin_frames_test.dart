import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runquest/features/home/home_screen.dart';
import 'package:runquest/features/home/live_map_controller.dart';
import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/profile_cosmetics.dart';
import 'package:runquest/features/run_history/run_history_controller.dart';
import 'package:runquest/shared/maps/run_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/live_map_fakes.dart';
import 'support/map_fakes.dart';
import 'support/run_history_fakes.dart';

/// 서버 규칙(가격·잔액·소유 확인)을 흉내 내는 지갑입니다.
class FakeWalletService implements WalletService {
  int coins = 0;
  int level = 1;
  final owned = <FrameKind>{};
  FrameKind? equipped;
  String color = '#3182F6';
  final calls = <String>[];

  static const prices = {FrameKind.basic: 300, FrameKind.aura: 1400};

  Wallet get _wallet => Wallet.fromJson({
    'coins': coins,
    'level': level,
    'level_coins': 10 * (level - 1) + 50 * (level ~/ 5),
    'next_reward_level': level + 1,
    'next_reward_coins': 10,
    'prices': {'basic': 300, 'aura': 1400},
    'owned': [for (final kind in owned) kind.code],
    'equipped': equipped?.code,
    'color': color,
  });

  @override
  bool get isCurrentOwner => true;

  @override
  Future<Wallet> load() async => _wallet;

  @override
  Future<Wallet> buyFrame(FrameKind kind) async {
    calls.add('buy:${kind.code}');
    if (!owned.contains(kind)) {
      if (coins < prices[kind]!) {
        throw const PostgrestException(message: '코인이 부족합니다.', code: 'P0001');
      }
      coins -= prices[kind]!;
      owned.add(kind);
    }
    return _wallet;
  }

  @override
  Future<Wallet> setFrame(FrameKind? kind, String value) async {
    calls.add('set:${kind?.code}:$value');
    if (kind != null && !owned.contains(kind)) {
      throw const PostgrestException(
        message: '가지고 있는 테두리만 착용할 수 있습니다.',
        code: '42501',
      );
    }
    equipped = kind;
    color = value;
    return _wallet;
  }
}

Widget itemPage(WalletController wallet) => MaterialApp(
  home: MediaQuery(
    // 오라 맥동 애니메이션 때문에 pumpAndSettle이 끝나지 않도록 멈춥니다.
    data: const MediaQueryData(disableAnimations: true, size: Size(400, 900)),
    child: Scaffold(body: ProfileCosmetics.store(wallet: wallet)),
  ),
);

ButtonStyleButton button(WidgetTester tester, String key, String label) =>
    tester.widget<ButtonStyleButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      ),
    );

void main() {
  test('코인 묶음은 1,100원부터 49,900원까지이고 큰 묶음일수록 보너스가 큽니다', () {
    expect(CoinPack.all.first.krw, 1100);
    expect(CoinPack.all.first.coins, 100);
    expect(CoinPack.all.last.krw, 49900);
    expect(
      [for (final pack in CoinPack.all) pack.bonus],
      [0, 0, 20, 80, 150, 400, 764],
    );
    // 1,100원 = 100코인 기준으로 기본 테두리는 3,300원, 오라 테두리는 15,400원입니다.
    expect(FrameKind.basic.defaultPrice * 11, 3300);
    expect(FrameKind.aura.defaultPrice * 11, 15400);
    expect(formatNumber(1234567), '1,234,567');
    expect(formatNumber(-700), '-700');
    expect(colorHex(const Color(0xFF12AB9F)), '#12AB9F');
    expect(hexColor('#12AB9F'), const Color(0xFF12AB9F));
  });

  test('코인으로 테두리를 사고 착용·색 변경은 서버 결과로 바꿉니다', () async {
    final service = FakeWalletService()..coins = 500;
    final wallet = WalletController(service);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    expect(await wallet.buy(FrameKind.aura), '코인이 부족합니다.');
    expect(await wallet.buy(FrameKind.basic), isNull);
    expect(wallet.wallet!.coins, 200);
    expect(await wallet.wear(FrameKind.basic), isNull);
    expect(wallet.equipped, FrameKind.basic);
    expect(await wallet.paint(const Color(0xFFEC4899)), isNull);
    expect(wallet.wallet!.color, '#EC4899');
    expect(wallet.equipped, FrameKind.basic);
    expect(await wallet.wear(null), isNull);
    expect(wallet.equipped, isNull);
    expect(wallet.wallet!.color, '#EC4899');
  });

  testWidgets('오른쪽 위 코인 수 옆 + 버튼으로 금액대별 충전 창을 엽니다', (tester) async {
    final service = FakeWalletService()..coins = 1234;
    final wallet = WalletController(service);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    await tester.pumpWidget(itemPage(wallet));
    await tester.pumpAndSettle();
    expect(find.text('1,234'), findsOneWidget);
    final title = tester.getCenter(find.text('아이템'));
    final coin = tester.getCenter(find.text('1,234'));
    expect(coin.dx, greaterThan(title.dx + 150));
    expect((coin.dy - title.dy).abs(), lessThan(20));

    await tester.tap(find.byTooltip('코인 충전'));
    await tester.pumpAndSettle();
    expect(find.text('코인 충전'), findsWidgets);
    // 결제 설정이 없는 미리보기에서는 가격만 보여주고 살 수 없습니다.
    expect(find.textContaining('미리보기에서는 가격만'), findsOneWidget);
    for (final price in ['1,100원', '3,300원', '5,500원', '11,000원']) {
      expect(find.text(price), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('49,900원'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('49,900원'), findsOneWidget);
    expect(find.text('보너스 +764코인'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('49,900원'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('상점에서 코인으로 테두리를 사고 보관함에서 착용·해제·색 변경을 합니다', (tester) async {
    final service = FakeWalletService()..coins = 1500;
    final wallet = WalletController(service);
    addTearDown(wallet.dispose);
    await wallet.refresh();
    await tester.pumpWidget(itemPage(wallet));
    await tester.pumpAndSettle();
    expect(find.textContaining('아직 테두리가 없어요'), findsOneWidget);

    await tester.tap(find.text('상점 보기'));
    await tester.pumpAndSettle();
    expect(find.text('300코인'), findsOneWidget);
    expect(find.text('1,400코인'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('shop-basic')),
        matching: find.text('구매'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '구매').last);
    await tester.pumpAndSettle();
    expect(service.calls, ['buy:basic']);
    expect(find.text('1,200'), findsOneWidget);
    expect(button(tester, 'shop-basic', '보유 중').onPressed, isNull);
    // 남은 코인으로 오라를 살 수 없으면 충전 버튼을 보여줍니다.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('shop-aura')),
        matching: find.text('코인 충전'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('보관함'));
    await tester.pumpAndSettle();
    expect(button(tester, 'frame-basic', '해제').onPressed, isNull);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('frame-basic')),
        matching: find.text('착용'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('착용 중'), findsOneWidget);
    expect(button(tester, 'frame-basic', '착용').onPressed, isNull);
    expect(button(tester, 'frame-basic', '해제').onPressed, isNotNull);

    await tester.tap(find.bySemanticsLabel('테두리 색 #EC4899'));
    await tester.pumpAndSettle();
    expect(service.color, '#EC4899');
    expect(service.equipped, FrameKind.basic);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('frame-basic')),
        matching: find.text('해제'),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.equipped, isNull);
    expect(find.text('착용 중'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('착용한 테두리를 고른 색으로 러닝 지도 내 위치 원에 보냅니다', (tester) async {
    final location = FakeLocationService();
    final history = RunHistoryController(
      FakeRunRecordService(),
      outbox: FakeRunOutbox(),
    );
    final map = LiveMapController(
      locationService: location,
      runnerService: FakeRunnerService(),
      runHistory: history,
    );
    addTearDown(location.updates.close);
    final service = FakeWalletService()..owned.add(FrameKind.aura);
    final wallet = WalletController(service);
    await wallet.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            controller: map,
            mapBridgeFactory: FakeMapBridge.new,
            wallet: wallet,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    RunMapFrame? frame() =>
        tester.widget<RunMap>(find.byType(RunMap)).positionFrame;
    expect(frame(), isNull);

    await wallet.paint(const Color(0xFFF97316));
    await wallet.wear(FrameKind.aura);
    await tester.pump();
    expect(frame()!.toJson(), {'style': 'aura', 'color': '#F97316'});

    await wallet.wear(null);
    await tester.pump();
    expect(frame(), isNull);

    await tester.pumpWidget(const SizedBox());
    wallet.dispose();
    map.dispose();
    history.dispose();
  });
}
