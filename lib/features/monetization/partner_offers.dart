import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PartnerOffers extends StatefulWidget {
  const PartnerOffers({required this.client, super.key});

  final SupabaseClient client;

  @override
  State<PartnerOffers> createState() => _PartnerOffersState();
}

class _PartnerOffersState extends State<PartnerOffers> {
  late final String? _owner = widget.client.auth.currentUser?.id;
  List<_Offer> _offers = [];
  bool _busy = false;
  AppLifecycleListener? _lifecycle;
  Timer? _expiry;

  bool get _isOwner =>
      mounted && _owner != null && widget.client.auth.currentUser?.id == _owner;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _expiry?.cancel();
    super.dispose();
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    final now = DateTime.now();
    final deadlines =
        _offers
            .map((offer) => offer.endsAt)
            .where((deadline) => deadline.isAfter(now))
            .toList()
          ..sort();
    if (deadlines.isEmpty) return;
    _expiry = Timer(deadlines.first.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _scheduleExpiry();
    });
  }

  Future<void> _refresh({String? offerId}) async {
    if (!_isOwner || _busy) return;
    setState(() => _busy = true);
    try {
      if (offerId != null) {
        await widget.client.rpc(
          'claim_shop_coupon',
          params: {'offer': offerId},
        );
      }
      if (!_isOwner) return;
      final rows = await widget.client
          .rpc<List<dynamic>>('active_shop_offers')
          .timeout(const Duration(seconds: 15));
      final offers = rows.map((row) => _Offer.fromJson(row as Map)).toList();
      if (_isOwner) {
        setState(() => _offers = offers);
        _scheduleExpiry();
      }
    } catch (_) {
      if (mounted && _isOwner && offerId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('쿠폰을 불러오지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String code) async {
    if (!_isOwner) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted && _isOwner) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('쿠폰 번호를 복사했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOwner) return const SizedBox.shrink();
    final now = DateTime.now();
    final offers = _offers.where((offer) => offer.endsAt.isAfter(now));
    if (offers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('러닝 매장 혜택', style: Theme.of(context).textTheme.titleMedium),
          for (final offer in offers)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.shop,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(offer.address),
                    Text(offer.terms),
                    Text(
                      '사용 기한: ${MaterialLocalizations.of(context).formatMediumDate(offer.endsAt.toLocal())} '
                      '${TimeOfDay.fromDateTime(offer.endsAt.toLocal()).format(context)}',
                    ),
                    if (offer.redeemed)
                      const Text('사용 완료')
                    else if (offer.code case final code?) ...[
                      const Text('매장 직원에게 이 쿠폰 번호를 보여 주세요.'),
                      SelectableText(code),
                      TextButton(
                        onPressed: () => _copy(code),
                        child: const Text('번호 복사'),
                      ),
                    ] else
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _refresh(offerId: offer.id),
                        child: const Text('쿠폰 받기'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Offer {
  _Offer.fromJson(Map row)
    : id = row['id'] as String,
      shop = row['shop_name'] as String,
      address = row['shop_address'] as String,
      terms = row['terms'] as String,
      endsAt = DateTime.parse(row['ends_at'] as String),
      code = row['code'] as String?,
      redeemed = row['redeemed'] == true;

  final String id;
  final String shop;
  final String address;
  final String terms;
  final DateTime endsAt;
  final String? code;
  final bool redeemed;
}
