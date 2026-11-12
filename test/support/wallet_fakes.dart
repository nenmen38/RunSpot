import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
