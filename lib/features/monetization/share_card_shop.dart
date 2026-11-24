import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../run_history/models/run_record.dart';
import '../run_history/run_history_controller.dart';
import '../run_share/data/share_image_renderer.dart';
import '../run_share/models/share_card_catalog.dart';
import 'coin_frames.dart';
import 'cosmetic_shop.dart';
import 'cosmetics.dart';

class ShareCardShop extends StatelessWidget {
  const ShareCardShop({
    required this.wallet,
    required this.onMessage,
    this.history,
    this.ownedOnly = false,
    super.key,
  });

  final WalletController wallet;
  final RunHistoryController? history;
  final ValueChanged<String> onMessage;
  final bool ownedOnly;

  Future<({Uint8List image, bool isSample})> _preview(CosmeticItem item) async {
    final source = history;
    RunRecord? record;
    if (source != null && source.service.isCurrentOwner) {
      if (source.visibleRecords.isEmpty) await source.refresh();
      if (source.service.isCurrentOwner) {
        record = source.visibleRecords.firstOrNull;
      }
    }
    final isSample = record == null;
    final image = await ShareImageRenderer().render(
      record ??
          RunRecord(
            id: 'sample',
            clientRunId: 'sample',
            startedAt: DateTime.utc(2026, 1, 1),
            endedAt: DateTime.utc(2026, 1, 1, 0, 28, 45),
            distanceMeters: 5000,
            durationSeconds: 1725,
          ),
      layout: shareCardLayouts[item]!,
      height: 1512,
    );
    return (image: image, isSample: isSample);
  }

  Future<void> _open(
    BuildContext context,
    CosmeticItem item, {
    bool buy = false,
  }) async {
    final current = wallet.wallet;
    if (current == null || !wallet.service.isCurrentOwner) return;
    final price = current.priceOf(item);
    if (buy &&
        (!await checkCoinBalance(context, current, price) ||
            !context.mounted)) {
      return;
    }
    final preview = _preview(item);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(item.label),
        content: FutureBuilder(
          future: preview,
          builder: (context, snapshot) {
            if (!wallet.service.isCurrentOwner) {
              return const Text('로그인 상태를 확인해 주세요.');
            }
            if (snapshot.hasError) return const Text('미리보기를 불러오지 못했습니다.');
            if (snapshot.data case final result?) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(result.isSample ? '예시 러닝' : '내 최근 러닝'),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      result.image,
                      height: 260,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          if (buy)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('${formatNumber(price)}코인으로 구매'),
            ),
        ],
      ),
    );
    if (confirmed != true ||
        !context.mounted ||
        !wallet.service.isCurrentOwner) {
      return;
    }
    if ((wallet.wallet?.coins ?? 0) < price) return;
    final error = await wallet.buyCosmetic(item, expectedPrice: price);
    if (context.mounted) {
      onMessage(error ?? '구매했어요. 러닝 공유 화면에서 카드를 골라 보세요.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: wallet,
    builder: (context, _) {
      final current = wallet.wallet;
      if (current == null) return const SizedBox.shrink();
      final items = ownedOnly
          ? shareCardLayouts.keys.where(current.cosmetics.contains)
          : shareCardLayouts.keys;
      if (items.isEmpty) return const SizedBox.shrink();
      final text = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Text(
            ownedOnly ? '내 공유 카드' : '러닝 공유 카드',
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (!ownedOnly) ...[
            const SizedBox(height: 2),
            Text(CosmeticSlot.shareCard.description, style: text.bodySmall),
          ],
          const SizedBox(height: 10),
          for (final item in items)
            CosmeticItemRow(
              key: ValueKey('${ownedOnly ? 'inventory' : 'shop'}-${item.code}'),
              item: item,
              subtitle: ownedOnly
                  ? '러닝 공유 화면에서 사용'
                  : current.listedCosmetics.contains(item) ||
                        current.cosmetics.contains(item)
                  ? '${formatNumber(current.priceOf(item))}코인'
                  : '${formatNumber(item.defaultPrice)}코인 · 판매 준비 중',
              onPreview: () => _open(context, item),
              trailing: ownedOnly
                  ? null
                  : current.cosmetics.contains(item)
                  ? const OutlinedButton(onPressed: null, child: Text('보유 중'))
                  : FilledButton(
                      onPressed:
                          wallet.busy || !current.listedCosmetics.contains(item)
                          ? null
                          : () => _open(context, item, buy: true),
                      child: const Text('구매'),
                    ),
            ),
        ],
      );
    },
  );
}
