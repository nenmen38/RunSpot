import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'item_inventory.dart';
import '../crew/crew_controller.dart';
import '../crew/widgets/crew_widgets.dart';
import 'cosmetic_shop.dart';
import 'coin_frames.dart';
import 'store_catalog.dart';
import 'share_card_shop.dart';
import '../run_history/run_history_controller.dart';

class ProfileCosmetics extends StatefulWidget {
  const ProfileCosmetics({required this.client, required this.child, super.key})
    : wallet = null,
      crew = null,
      history = null;

  const ProfileCosmetics.store({
    this.client,
    this.wallet,
    this.crew,
    this.history,
    super.key,
  }) : child = null;

  final SupabaseClient? client;
  final Widget? child;

  /// 코인 잔액과 코인 테두리입니다. 아이템 페이지 머리·보관함·상점에 씁니다.
  final WalletController? wallet;

  /// 크루 생성권을 사용해 크루를 만들 때 씁니다.
  final CrewController? crew;
  final RunHistoryController? history;

  @override
  State<ProfileCosmetics> createState() => _ProfileCosmeticsState();
}

class _ProfileCosmeticsState extends State<ProfileCosmetics> {
  // 출시에서 결제를 별도로 켜기 전에는 스토어 SDK를 초기화하지 않습니다.
  static const _paymentsEnabled = bool.fromEnvironment(
    'IN_APP_PAYMENTS_ENABLED',
  );
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  // 스토어 SDK는 전역 계정을 사용하므로 구매와 계정 전환을 직렬화합니다.
  static Future<void> _queue = Future.value();

  late final String? _owner = widget.client?.auth.currentUser?.id;
  // 저장소는 로그인 계정이 있을 때만 씁니다. 미리보기에서는 착용 상태를 화면에만 둡니다.
  late final _prefs = SharedPreferencesAsync();

  /// 스토어에 등록된 코인 묶음입니다. 상품 ID로 찾습니다.
  Map<String, Package> _coinPackages = {};
  Set<Cosmetic> _owned = {};
  Set<Cosmetic> _selected = {};
  String? _customerId;
  bool _busy = false;
  String? _message;

  /// 아이템 페이지에서 보는 칸입니다. 0은 보관함, 1은 상점입니다.
  int _section = 0;

  bool get _isStore => widget.child == null;
  bool get _previewOnly => _key.isEmpty || widget.client == null;

  String get _key => !_paymentsEnabled || kIsWeb
      ? ''
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => _androidKey,
          TargetPlatform.iOS => _iosKey,
          _ => '',
        };

  bool get _isOwner =>
      mounted &&
      _owner != null &&
      widget.client?.auth.currentUser?.id == _owner;

  String _preference(Cosmetic item) =>
      'profile-cosmetic:${widget.client!.rest.url}:$_owner:${item.id}';

  @override
  void initState() {
    super.initState();
    if (!_previewOnly) _run(_load);
  }

  void _equip(Cosmetic item, bool selected) {
    if (!_busy) unawaited(_run(() => _toggle(item, selected)));
  }

  void _requireOwner() {
    if (!_isOwner) throw StateError('계정이 변경되었습니다.');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_previewOnly || !_isOwner || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final operation = _queue.then((_) async {
      _requireOwner();
      final customerId = _customerId ??= await widget.client!
          .rpc<String>('cosmetic_customer')
          .timeout(const Duration(seconds: 15));
      _requireOwner();
      if (!await Purchases.isConfigured) {
        _requireOwner();
        await Purchases.configure(
          PurchasesConfiguration(_key)
            ..appUserID = customerId
            ..entitlementVerificationMode =
                EntitlementVerificationMode.informational,
        );
      } else if (await Purchases.appUserID != customerId) {
        _requireOwner();
        await Purchases.logIn(customerId);
      }
      _requireOwner();
      await action();
    });
    _queue = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await operation;
    } on PlatformException catch (error) {
      if (_isOwner &&
          PurchasesErrorHelper.getErrorCode(error) !=
              PurchasesErrorCode.purchaseCancelledError) {
        setState(
          () => _message =
              PurchasesErrorHelper.getErrorCode(error) ==
                  PurchasesErrorCode.paymentPendingError
              ? '결제 승인 대기 중입니다. 승인 후 코인 거래 내역을 확인해 주세요.'
              : '스토어 요청을 완료하지 못했습니다. 다시 시도해 주세요.',
        );
      }
    } catch (_) {
      if (_isOwner) setState(() => _message = '꾸미기 정보를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final info = await Purchases.getCustomerInfo();
    await _apply(info);
    if (!_isStore) return;
    _requireOwner();
    final offerings = await Purchases.getOfferings();
    _requireOwner();
    final coins = offerings.all['coin_packs']?.availablePackages ?? [];
    setState(() {
      _coinPackages = {
        for (final pack in CoinPack.all)
          for (final package in coins)
            if (pack.id == package.identifier &&
                pack.id == package.storeProduct.identifier &&
                package.storeProduct.productCategory ==
                    ProductCategory.nonSubscription)
              pack.id: package,
      };
    });
  }

  Future<void> _apply(CustomerInfo info) async {
    final owned = <Cosmetic>{};
    final selected = <Cosmetic>{};
    for (final item in Cosmetic.values) {
      final entitlement = info.entitlements.active[item.id];
      if (entitlement == null ||
          !{
            VerificationResult.verified,
            VerificationResult.verifiedOnDevice,
          }.contains(entitlement.verification)) {
        continue;
      }
      owned.add(item);
      if (await _prefs.getBool(_preference(item)) == true) selected.add(item);
    }
    _requireOwner();
    setState(() {
      _owned = owned;
      _selected = selected;
    });
  }

  /// 코인은 서버가 결제 알림(웹훅)을 받아 기록하므로 반영될 때까지 잠시 다시 확인합니다.
  Future<void> _buyCoins(CoinPack pack) async {
    if (!_paymentsEnabled) return;
    final package = _coinPackages[pack.id];
    final wallet = widget.wallet;
    if (package == null || wallet == null) return;
    final result = await Purchases.purchase(PurchaseParams.package(package));
    _requireOwner();
    setState(() => _message = '결제를 확인하고 있어요.');
    final transactionId = result.storeTransaction.transactionIdentifier;
    final status = transactionId.isEmpty
        ? const CoinPurchaseStatus(CoinPurchaseState.pending)
        : await wallet.waitForPurchase(transactionId);
    _requireOwner();
    setState(
      () => _message = switch (status.state) {
        CoinPurchaseState.credited =>
          '${formatNumber(status.coins!)}코인을 충전했어요.',
        CoinPurchaseState.refunded => '이 결제는 환불되어 코인이 적립되지 않았어요.',
        CoinPurchaseState.pending => '코인 적립을 확인하고 있어요. 잠시 후 거래 내역을 확인해 주세요.',
      },
    );
  }

  Future<void> _openCoins() async {
    final wallet = widget.wallet;
    if (wallet == null) return;
    unawaited(wallet.refresh());
    final pack = await showModalBottomSheet<CoinPack>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: wallet,
        builder: (context, _) => CoinShopSheet(
          controller: wallet,
          showPurchases: _paymentsEnabled,
          prices: {
            if (!_previewOnly && !_busy && wallet.wallet?.weeklyQuest != null)
              for (final entry in _coinPackages.entries)
                entry.key: entry.value.storeProduct.priceString,
          },
          note: !_paymentsEnabled
              ? null
              : _previewOnly
              ? '결제 설정이 없는 미리보기에서는 가격만 볼 수 있어요.'
              : wallet.wallet?.weeklyQuest == null
              ? '코인 상점 정보를 확인할 수 없어 충전이 일시적으로 불가능합니다.'
              : _coinPackages.isEmpty
              ? '스토어에서 코인 상품을 불러오지 못했어요.'
              : null,
          onBuy: (pack) => Navigator.pop(context, pack),
        ),
      ),
    );
    if (pack != null && _isOwner) await _run(() => _buyCoins(pack));
  }

  /// 보관함의 크루 생성권 "사용하기": 크루 이름·설명·아이콘을 고르는 창을 엽니다.
  Future<void> _useCrewTicket() async {
    final crew = widget.crew;
    if (crew == null) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CreateCrewSheet(controller: crew),
    );
    if (created != true || !mounted) return;
    unawaited(widget.wallet?.refresh());
    _showMessage('${crew.crew?.name ?? '크루'}를 만들었어요. 소셜 탭의 크루에서 볼 수 있어요.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(Cosmetic item, bool selected) async {
    await _apply(await Purchases.getCustomerInfo());
    _requireOwner();
    if (!_owned.contains(item)) return;
    await _prefs.setBool(_preference(item), selected);
    _requireOwner();
    setState(() {
      if (selected) {
        _selected.add(item);
      } else {
        _selected.remove(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child case final profile?) {
      return _isOwner ? decorateProfile(profile, _selected) : profile;
    }
    final text = Theme.of(context).textTheme;
    // 상점에는 코인 테두리와 크루 생성권만 둡니다. (블루 컬렉션·꾸미기 아이템은 판매하지 않습니다.)
    final store = ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        switch (widget.wallet) {
          final wallet? => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FrameShop(controller: wallet, onMessage: _showMessage),
              ShareCardShop(
                wallet: wallet,
                history: widget.history,
                onMessage: _showMessage,
              ),
              CosmeticShop(controller: wallet, onMessage: _showMessage),
              if (widget.crew case final crew?)
                CrewExpansionShop(
                  controller: wallet,
                  crew: crew,
                  onMessage: _showMessage,
                ),
            ],
          ),
          null => const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('상점을 불러오는 중이에요.')),
          ),
        },
      ],
    );
    final inventory = ItemInventory(
      items: [
        for (final item in Cosmetic.values)
          if (_owned.contains(item))
            InventoryItem(item, equipped: _selected.contains(item)),
      ],
      onChanged: _equip,
      busy: _busy,
      message: _message,
      header: switch (widget.wallet) {
        final wallet? => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FrameInventory(
              controller: wallet,
              onShop: () => setState(() => _section = 1),
              onMessage: _showMessage,
              onUseCrewTicket: widget.crew == null ? null : _useCrewTicket,
            ),
            CosmeticInventory(controller: wallet, onMessage: _showMessage),
            ShareCardShop(
              wallet: wallet,
              history: widget.history,
              onMessage: _showMessage,
              ownedOnly: true,
            ),
          ],
        ),
        null => null,
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // 아주 큰 글씨에서도 코인 잔액과 겹치지 않게 제목이 줄어듭니다.
            Flexible(
              child: Text(
                '아이템',
                style: text.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.wallet == null || (_paymentsEnabled && _previewOnly)) ...[
              const SizedBox(width: 8),
              const StoreTag('미리보기'),
            ],
            const Spacer(),
            // 결제를 꺼도 코인 잔액과 거래 내역은 열 수 있습니다.
            if (widget.wallet case final wallet?)
              CoinBalance(
                controller: wallet,
                showPurchases: _paymentsEnabled,
                onOpen: _openCoins,
              ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.inventory_2_outlined),
              label: Text('보관함'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.storefront_outlined),
              label: Text('상점'),
            ),
          ],
          selected: {_section},
          onSelectionChanged: (value) =>
              setState(() => _section = value.single),
        ),
        const SizedBox(height: 16),
        Expanded(child: _section == 0 ? inventory : store),
      ],
    );
  }
}
