import 'package:runquest/features/monetization/coin_frames.dart';
import 'package:runquest/features/monetization/cosmetics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 서버 규칙(가격·잔액·소유 확인)을 흉내 내는 지갑입니다.
class FakeWalletService implements WalletService {
  int coins = 0;
  int level = 1;
  final owned = <FrameKind>{};
  FrameKind? equipped;
  String color = '#3182F6';
  final calls = <String>[];
  final purchaseStatuses = <String, CoinPurchaseStatus>{};
  final weeklyQuests = <WeeklyCoinQuest>[];
  final claimedQuests = <String>{};

  static const prices = {FrameKind.basic: 300, FrameKind.aura: 1400};

  Wallet get _wallet => Wallet.fromJson({
    'coins': coins,
    'level': level,
    'level_coins': 10 * (level - 1) + 50 * (level ~/ 5),
    'next_reward_level': level + 1,
    'next_reward_coins': 10,
    'weekly_quests': [
      for (final quest in weeklyQuests)
        {
          'code': quest.code,
          'progress': quest.progress,
          'goal': quest.goal,
          'reward': quest.reward,
          'awarded': quest.awarded || claimedQuests.contains(quest.code),
        },
    ],
    'prices': {'basic': 300, 'aura': 1400},
    'owned': [for (final kind in owned) kind.code],
    'equipped': equipped?.code,
    'color': color,
    'crew_tickets': crewTickets,
    'in_crew': inCrew,
    'cosmetics': {
      'owned': [for (final item in cosmetics) item.code],
      'equipped': {
        for (final entry in equippedCosmetics.entries)
          entry.key.code: entry.value.code,
      },
    },
  });

  final cosmetics = <CosmeticItem>{};
  final equippedCosmetics = <CosmeticSlot, CosmeticItem>{};
  final expandedCrews = <String>{};

  @override
  Future<Wallet> buyCosmetic(CosmeticItem item, {int? expectedPrice}) async {
    calls.add('buy:${item.code}');
    if (!cosmetics.contains(item)) {
      if (coins < item.defaultPrice) {
        throw const PostgrestException(message: '코인이 부족합니다.', code: 'P0001');
      }
      coins -= item.defaultPrice;
      cosmetics.add(item);
    }
    return _wallet;
  }

  @override
  Future<Wallet> equipCosmetic(CosmeticSlot slot, CosmeticItem? item) async {
    calls.add('equip:${slot.code}:${item?.code}');
    if (item == null) {
      equippedCosmetics.remove(slot);
    } else {
      if (!cosmetics.contains(item)) {
        throw const PostgrestException(
          message: '가진 아이템만 착용할 수 있습니다.',
          code: 'P0001',
        );
      }
      equippedCosmetics[slot] = item;
    }
    return _wallet;
  }

  @override
  Future<Wallet> expandCrew(String crewId) async {
    calls.add('expand:$crewId');
    if (expandedCrews.contains(crewId)) {
      throw const PostgrestException(message: '이미 정원을 늘린 크루예요.', code: 'P0001');
    }
    if (coins < 1000) {
      throw const PostgrestException(message: '코인이 부족합니다.', code: 'P0001');
    }
    coins -= 1000;
    expandedCrews.add(crewId);
    return _wallet;
  }

  @override
  bool get isCurrentOwner => true;

  @override
  Future<CoinPurchaseStatus> coinPurchaseStatus(String transactionId) async {
    calls.add('transaction:$transactionId');
    return purchaseStatuses[transactionId] ??
        const CoinPurchaseStatus(CoinPurchaseState.pending);
  }

  @override
  Future<Wallet> load() async => _wallet;

  @override
  Future<Wallet> claimWeeklyQuest(String code) async {
    calls.add('claim:$code');
    final quest = weeklyQuests.firstWhere((quest) => quest.code == code);
    if (!quest.completed) {
      throw const PostgrestException(
        message: '이번 주 퀘스트를 아직 완료하지 않았습니다.',
        code: 'P0001',
      );
    }
    if (!quest.awarded && claimedQuests.add(code)) coins += quest.reward;
    return _wallet;
  }

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

  int crewTickets = 0;
  bool inCrew = false;

  @override
  Future<Wallet> buyCrewTicket() async {
    calls.add('buy:crew_ticket');
    if (crewTickets > 0) {
      throw const PostgrestException(
        message: '사용하지 않은 크루 생성권이 이미 있어요.',
        code: 'P0001',
      );
    }
    if (coins < 640) {
      throw const PostgrestException(message: '코인이 부족합니다.', code: 'P0001');
    }
    coins -= 640;
    crewTickets++;
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
