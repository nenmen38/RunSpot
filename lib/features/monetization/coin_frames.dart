import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/errors/server_error.dart';
import '../../shared/theme/app_colors.dart';

/// 코인으로 사는 테두리입니다. 가격은 서버가 정하며 여기 값은 서버 응답이 없을 때만 씁니다.
enum FrameKind {
  basic('basic', '기본 테두리', '원하는 색의 깔끔한 테두리', 300),
  aura('aura', '오라 테두리', '테두리 색으로 은은하게 빛나는 오라', 1400);

  const FrameKind(this.code, this.label, this.description, this.defaultPrice);
  final String code;
  final String label;
  final String description;
  final int defaultPrice;

  static FrameKind? fromCode(Object? code) =>
      values.where((kind) => kind.code == code).firstOrNull;
}

/// 테두리 색 고르기에 보여주는 색입니다. 서버는 #RRGGBB 형식이면 모두 받습니다.
const framePalette = [
  Color(0xFF3182F6),
  Color(0xFF38BDF8),
  Color(0xFF14B8A6),
  Color(0xFF22C55E),
  Color(0xFF84CC16),
  Color(0xFFFACC15),
  Color(0xFFF97316),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF94A3B8),
  Color(0xFF111827),
];

String colorHex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Color hexColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// 스토어 코인 묶음입니다. 상품 ID와 코인 수는 서버의 coin_pack_coins와 같아야 합니다.
class CoinPack {
  const CoinPack(this.id, this.krw, this.coins);
  final String id;
  final int krw;
  final int coins;

  /// 1,100원 = 100코인 기준보다 더 주는 코인입니다.
  int get bonus => coins - krw ~/ 11;

  static const all = [
    CoinPack('coins_1100', 1100, 100),
    CoinPack('coins_3300', 3300, 300),
    CoinPack('coins_5500', 5500, 520),
    CoinPack('coins_11000', 11000, 1080),
    CoinPack('coins_16500', 16500, 1650),
    CoinPack('coins_33000', 33000, 3400),
    CoinPack('coins_49900', 49900, 5300),
  ];
}

String formatNumber(int value) {
  final text = value.abs().toString();
  final grouped = text.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return value < 0 ? '-$grouped' : grouped;
}

/// 서버가 계산한 내 코인과 테두리 상태입니다.
class Wallet {
  Wallet.fromJson(Map<String, dynamic> json)
    : coins = json['coins'] as int,
      level = json['level'] as int,
      levelCoins = json['level_coins'] as int,
      nextRewardLevel = json['next_reward_level'] as int?,
      nextRewardCoins = json['next_reward_coins'] as int?,
      prices = {
        for (final kind in FrameKind.values)
          kind:
              (json['prices'] as Map?)?[kind.code] as int? ?? kind.defaultPrice,
      },
      owned = {
        for (final code in json['owned'] as List? ?? const [])
          ?FrameKind.fromCode(code),
      },
      equipped = FrameKind.fromCode(json['equipped']),
      color = json['color'] as String? ?? '#3182F6';

  final int coins;
  final int level;
  final int levelCoins;
  final int? nextRewardLevel;
  final int? nextRewardCoins;
  final Map<FrameKind, int> prices;
  final Set<FrameKind> owned;
  final FrameKind? equipped;
  final String color;
}

abstract interface class WalletService {
  bool get isCurrentOwner;
  Future<Wallet> load();
  Future<Wallet> buyFrame(FrameKind kind);

  /// [kind]가 null이면 테두리를 해제합니다. 색은 그대로 저장합니다.
  Future<Wallet> setFrame(FrameKind? kind, String color);
}

class SupabaseWalletService implements WalletService {
  SupabaseWalletService(this.client) : _owner = client.auth.currentUser?.id;
  final SupabaseClient client;
  final String? _owner;

  @override
  bool get isCurrentOwner =>
      _owner != null && client.auth.currentSession?.user.id == _owner;

  Future<Wallet> _rpc(String name, [Map<String, dynamic>? params]) async {
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    final session = client.auth.currentSession!;
    final result = await client
        .rpc(name, params: params)
        .setHeader('Authorization', 'Bearer ${session.accessToken}');
    if (!isCurrentOwner) throw const AuthException('계정이 변경되었습니다.');
    return Wallet.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<Wallet> load() => _rpc('my_wallet');

  @override
  Future<Wallet> buyFrame(FrameKind kind) =>
      _rpc('buy_frame', {'requested_frame': kind.code});

  @override
  Future<Wallet> setFrame(FrameKind? kind, String color) => _rpc('set_frame', {
    'requested_frame': kind?.code,
    'requested_color': color,
  });
}

/// 코인 잔액과 테두리 구매·착용을 관리합니다. 모든 결과는 서버가 돌려준 지갑으로 바꿉니다.
class WalletController extends ChangeNotifier {
  WalletController(this.service);

  final WalletService service;
  static const _timeout = Duration(seconds: 15);
  bool _disposed = false;
  int _generation = 0;
  Wallet? wallet;
  bool loading = false;
  bool busy = false;
  String? error;

  /// 지도 내 위치 원에 두를 테두리입니다.
  FrameKind? get equipped => wallet?.equipped;
  Color get color => hexColor(wallet?.color ?? '#3182F6');

  String _message(Object exception, String fallback) => switch (exception) {
    AuthException() => '다시 로그인해 주세요.',
    TimeoutException() => '응답이 지연됩니다. 잠시 후 다시 확인해 주세요.',
    PostgrestException(:final code?, :final message)
        when {'42501', '22023', 'P0001'}.contains(code) =>
      message,
    _ => unexpectedServerError(exception, fallback),
  };

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await service.load().timeout(_timeout);
      if (_disposed || generation != _generation) return;
      wallet = result;
    } catch (exception) {
      if (_disposed || generation != _generation) return;
      error = _message(exception, '코인 정보를 불러오지 못했습니다.');
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<String?> _change(
    Future<Wallet> Function() action,
    String fallback,
  ) async {
    if (_disposed || busy) return null;
    busy = true;
    ++_generation;
    notifyListeners();
    String? failure;
    try {
      final result = await action().timeout(_timeout);
      if (!_disposed) wallet = result;
    } catch (exception) {
      failure = _message(exception, fallback);
    }
    if (_disposed) return failure;
    busy = false;
    notifyListeners();
    return failure;
  }

  Future<String?> buy(FrameKind kind) =>
      _change(() => service.buyFrame(kind), '테두리를 사지 못했습니다.');

  Future<String?> wear(FrameKind? kind) => _change(
    () => service.setFrame(kind, wallet?.color ?? '#3182F6'),
    '테두리를 바꾸지 못했습니다.',
  );

  Future<String?> paint(Color color) => _change(
    () => service.setFrame(wallet?.equipped, colorHex(color)),
    '테두리 색을 바꾸지 못했습니다.',
  );

  /// 결제 후 서버가 웹훅으로 코인을 기록할 때까지 잠시 다시 확인합니다.
  Future<bool> waitForCoins(int before, {int attempts = 5}) async {
    for (var i = 0; i < attempts && !_disposed; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await refresh();
      if ((wallet?.coins ?? before) > before) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}

/// 테두리 미리보기입니다. 지도 위 내 위치 원과 같은 모양으로 그립니다.
class FrameBadge extends StatefulWidget {
  const FrameBadge({
    required this.kind,
    required this.color,
    this.size = 44,
    super.key,
  });

  final FrameKind kind;
  final Color color;
  final double size;

  @override
  State<FrameBadge> createState() => _FrameBadgeState();
}

class _FrameBadgeState extends State<FrameBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 동작 줄이기 설정에서는 빛만 남기고 맥동하지 않습니다.
    if (widget.kind == FrameKind.aura &&
        !MediaQuery.disableAnimationsOf(context)) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void didUpdateWidget(covariant FrameBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) didChangeDependencies();
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final aura = widget.kind == FrameKind.aura;
    Widget circle(double t) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: widget.color,
          width: (aura ? 4 : 3) * size / 34,
        ),
        boxShadow: aura
            ? [
                BoxShadow(
                  color: widget.color.withValues(alpha: .6),
                  blurRadius: 8 + 10 * t,
                  spreadRadius: 2 + 6 * t,
                ),
              ]
            : const [],
      ),
      child: Icon(
        Icons.directions_run,
        size: size * .52,
        color: const Color(0xFF334155),
      ),
    );
    final pulse = _pulse;
    return SizedBox.square(
      dimension: size * 1.5,
      child: Center(
        child: pulse == null
            ? circle(.5)
            : AnimatedBuilder(
                animation: pulse,
                builder: (context, _) => circle(pulse.value),
              ),
      ),
    );
  }
}

/// 아이템 페이지 오른쪽 위의 코인 잔액과 충전 버튼입니다.
class CoinBalance extends StatelessWidget {
  const CoinBalance({required this.controller, required this.onAdd, super.key});

  final WalletController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final coins = controller.wallet?.coins;
      return Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7DB),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.monetization_on,
              size: 18,
              color: Color(0xFFEAB308),
            ),
            const SizedBox(width: 4),
            Text(
              coins == null ? '-' : formatNumber(coins),
              semanticsLabel: coins == null
                  ? '코인 정보 없음'
                  : '보유 코인 ${formatNumber(coins)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            IconButton(
              tooltip: '코인 충전',
              visualDensity: VisualDensity.compact,
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle, color: Color(0xFFEAB308)),
            ),
          ],
        ),
      );
    },
  );
}

/// 코인 충전 창입니다. 결제가 준비되지 않았으면 가격만 보여줍니다.
class CoinShopSheet extends StatelessWidget {
  const CoinShopSheet({
    required this.controller,
    required this.prices,
    required this.onBuy,
    this.note,
    super.key,
  });

  final WalletController controller;

  /// 스토어가 알려준 표시 가격입니다. 없는 묶음은 살 수 없습니다.
  final Map<String, String> prices;
  final ValueChanged<CoinPack> onBuy;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final wallet = controller.wallet;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text('코인 충전', style: text.titleLarge),
          if (wallet != null) ...[
            const SizedBox(height: 4),
            Text(
              '보유 ${formatNumber(wallet.coins)}코인 · 레벨 보상으로 받은 코인 '
              '${formatNumber(wallet.levelCoins)}',
              style: text.bodySmall,
            ),
            if (wallet.nextRewardLevel case final level?)
              Text(
                'Lv $level이 되면 ${wallet.nextRewardCoins}코인을 더 받아요.',
                style: text.bodySmall?.copyWith(color: AppColors.blueDark),
              ),
          ],
          if (note case final message?) ...[
            const SizedBox(height: 8),
            Text(message, style: text.bodySmall),
          ],
          const SizedBox(height: 12),
          for (final pack in CoinPack.all)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                key: ValueKey(pack.id),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.line),
                ),
                leading: const Icon(
                  Icons.monetization_on,
                  color: Color(0xFFEAB308),
                ),
                title: Text(
                  '${formatNumber(pack.coins)}코인',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: pack.bonus > 0
                    ? Text('보너스 +${formatNumber(pack.bonus)}코인')
                    : null,
                trailing: FilledButton(
                  onPressed: prices.containsKey(pack.id)
                      ? () => onBuy(pack)
                      : null,
                  child: Text(prices[pack.id] ?? '${formatNumber(pack.krw)}원'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 보관함 맨 위의 내 테두리입니다. 착용은 하나만, 해제는 착용 중일 때만 됩니다.
class FrameInventory extends StatelessWidget {
  const FrameInventory({
    required this.controller,
    required this.onShop,
    required this.onMessage,
    super.key,
  });

  final WalletController controller;
  final VoidCallback onShop;
  final ValueChanged<String> onMessage;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final wallet = controller.wallet;
      Future<void> run(Future<String?> action) async {
        if (await action case final message?) onMessage(message);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '내 테두리',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('착용하면 러닝 지도에서 내 위치 원에 표시돼요.', style: text.bodySmall),
          const SizedBox(height: 10),
          if (controller.loading && wallet == null)
            const LinearProgressIndicator(),
          if (controller.error case final message? when wallet == null)
            Row(
              children: [
                Expanded(child: Text(message)),
                TextButton(
                  onPressed: controller.refresh,
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          if (wallet != null && wallet.owned.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.blueSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('아직 테두리가 없어요.\n상점에서 코인으로 살 수 있어요.'),
                  ),
                  TextButton(onPressed: onShop, child: const Text('상점 보기')),
                ],
              ),
            ),
          if (wallet != null)
            for (final kind in FrameKind.values)
              if (wallet.owned.contains(kind))
                _OwnedFrame(
                  kind: kind,
                  color: controller.color,
                  equipped: wallet.equipped == kind,
                  busy: controller.busy,
                  onWear: () => run(controller.wear(kind)),
                  onRemove: () => run(controller.wear(null)),
                ),
          if (wallet != null && wallet.owned.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('테두리 색', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in framePalette)
                  _Swatch(
                    color: color,
                    selected: colorHex(color) == wallet.color,
                    onTap: controller.busy
                        ? null
                        : () => run(controller.paint(color)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      );
    },
  );
}

class _OwnedFrame extends StatelessWidget {
  const _OwnedFrame({
    required this.kind,
    required this.color,
    required this.equipped,
    required this.busy,
    required this.onWear,
    required this.onRemove,
  });

  final FrameKind kind;
  final Color color;
  final bool equipped;
  final bool busy;
  final VoidCallback onWear;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: ValueKey('frame-${kind.code}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: equipped ? AppColors.blue : AppColors.line,
          width: equipped ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: FrameBadge(kind: kind, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      kind.label,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (equipped)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            '착용 중',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Text(kind.description, style: text.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: busy || equipped ? null : onWear,
                        child: const Text('착용'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // 해제는 착용 중일 때만 누를 수 있습니다.
                      child: OutlinedButton(
                        onPressed: busy || !equipped ? null : onRemove,
                        child: const Text('해제'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '테두리 색 ${colorHex(color)}',
    child: InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.ink : Colors.white,
            width: 3,
          ),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3)],
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    ),
  );
}

/// 상점 맨 위의 코인 테두리 판매 목록입니다.
class FrameShop extends StatelessWidget {
  const FrameShop({
    required this.controller,
    required this.onCharge,
    required this.onMessage,
    super.key,
  });

  final WalletController controller;
  final VoidCallback onCharge;
  final ValueChanged<String> onMessage;

  Future<void> _buy(BuildContext context, FrameKind kind, int price) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${kind.label}를 살까요?'),
        content: Text(
          '${formatNumber(price)}코인을 사용합니다. 색은 산 뒤에 자유롭게 바꿀 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('구매'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    onMessage(await controller.buy(kind) ?? '${kind.label}를 보관함에 넣었어요.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final wallet = controller.wallet;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '코인 테두리',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final kind in FrameKind.values)
            Builder(
              builder: (context) {
                final price = wallet?.prices[kind] ?? kind.defaultPrice;
                final owned = wallet?.owned.contains(kind) ?? false;
                final short = wallet != null && wallet.coins < price;
                return Container(
                  key: ValueKey('shop-${kind.code}'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: FrameBadge(kind: kind, color: controller.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kind.label,
                              style: text.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(kind.description, style: text.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              '${formatNumber(price)}코인',
                              style: text.labelLarge?.copyWith(
                                color: AppColors.blueDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (owned)
                        const FilledButton(onPressed: null, child: Text('보유 중'))
                      else if (short)
                        OutlinedButton(
                          onPressed: onCharge,
                          child: const Text('코인 충전'),
                        )
                      else
                        FilledButton(
                          onPressed: wallet == null || controller.busy
                              ? null
                              : () => _buy(context, kind, price),
                          child: const Text('구매'),
                        ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
        ],
      );
    },
  );
}
