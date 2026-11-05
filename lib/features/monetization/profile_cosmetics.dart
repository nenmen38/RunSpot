import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'store_catalog.dart';

class ProfileCosmetics extends StatefulWidget {
  const ProfileCosmetics({
    required this.client,
    required this.child,
    super.key,
  });

  const ProfileCosmetics.store({this.client, super.key}) : child = null;

  final SupabaseClient? client;
  final Widget? child;

  @override
  State<ProfileCosmetics> createState() => _ProfileCosmeticsState();
}

class _ProfileCosmeticsState extends State<ProfileCosmetics> {
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const _iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  // 스토어 SDK는 전역 계정을 사용하므로 구매와 계정 전환을 직렬화합니다.
  static Future<void> _queue = Future.value();

  late final String? _owner = widget.client?.auth.currentUser?.id;
  final _prefs = SharedPreferencesAsync();
  Map<Cosmetic, Package> _packages = {};
  Set<Cosmetic> _owned = {};
  Set<Cosmetic> _selected = {};
  String? _customerId;
  bool _busy = false;
  bool _loaded = false;
  String? _message;

  bool get _isStore => widget.child == null;
  bool get _previewOnly => _key.isEmpty || widget.client == null;

  String get _key => kIsWeb
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

  void _requireOwner() {
    if (!_isOwner) throw StateError('계정이 변경되었습니다.');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_isOwner || _busy) return;
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
              ? '결제 승인 대기 중입니다. 승인 후 구매 복원을 눌러 주세요.'
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
    final packages =
        offerings.all['profile_cosmetics']?.availablePackages ?? [];
    setState(() {
      _packages = {
        for (final item in Cosmetic.values)
          for (final package in packages)
            if (item.id == package.identifier &&
                package.storeProduct.productCategory ==
                    ProductCategory.nonSubscription)
              item: package,
      };
      _loaded = true;
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

  Future<void> _buy(Cosmetic item, Package package) async {
    final result = await Purchases.purchase(PurchaseParams.package(package));
    await _apply(result.customerInfo);
    _requireOwner();
    if (!_owned.contains(item)) {
      setState(() => _message = '구매 권한이 아직 확인되지 않았습니다. 구매 복원을 눌러 주세요.');
    }
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

  Future<void> _restore() async {
    await _apply(await Purchases.restorePurchases());
    _requireOwner();
    setState(
      () => _message = _owned.isEmpty ? '복원할 꾸미기 아이템이 없습니다.' : '구매 내역을 복원했습니다.',
    );
  }

  Future<void> _openItem(Cosmetic item) async {
    final package = _packages[item];
    final owned = _owned.contains(item);
    final selected = _selected.contains(item);
    final canAct = !_previewOnly && !_busy && (owned || package != null);
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CosmeticArtwork(item: item, large: true),
              ),
              const SizedBox(height: 20),
              Text(
                item.label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(item.description),
              const SizedBox(height: 18),
              if (canAct)
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    owned
                        ? (selected ? '적용 해제' : '프로필에 적용')
                        : '${package!.storeProduct.priceString} 구매',
                  ),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
            ],
          ),
        ),
      ),
    );
    if (proceed != true || !_isOwner || !canAct) return;
    if (owned) {
      await _run(() => _toggle(item, !selected));
    } else {
      await _run(() => _buy(item, package!));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.child case final profile?) {
      return _isOwner ? decorateProfile(profile, _selected) : profile;
    }
    return StoreCatalog(
      previewOnly: _previewOnly,
      items: {
        for (final item in Cosmetic.values)
          if (_previewOnly)
            item: '자세히 보기'
          else if (_owned.contains(item))
            item: _selected.contains(item) ? '적용 중' : '보유 중'
          else if (_packages[item] case final package?)
            item: package.storeProduct.priceString,
      },
      onOpen: _openItem,
      onRestore: _previewOnly || _busy ? null : () => _run(_restore),
      onRetry: !_previewOnly && !_busy && !_loaded && _message != null
          ? () => _run(_load)
          : null,
      message: _message,
      loading: _busy,
    );
  }
}
