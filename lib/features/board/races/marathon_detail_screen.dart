import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/theme/app_colors.dart';
import '../widgets/board_post_tile.dart';
import '../widgets/board_theme.dart';
import 'marathon_event.dart';
import 'marathon_style.dart';
import 'marathon_status_badge.dart';

class MarathonDetailScreen extends StatelessWidget {
  const MarathonDetailScreen({required this.event, super.key});
  final MarathonEvent event;

  @override
  Widget build(BuildContext context) => BoardTheme(
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('러닝 대회')),
      bottomNavigationBar: event.website == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: SizedBox(
                child: FilledButton(
                  onPressed: () => _openWebsite(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.blueDark,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '공식 사이트',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: MarathonStatusBadge(status: event.status),
          ),
          const SizedBox(height: 12),
          Text(
            event.name,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _row(
                  '일정',
                  '${formatRaceDate(event.date)}${event.field('event', 'startTime') == null ? '' : ' · ${event.field('event', 'startTime')}'}',
                ),
                _row('장소', event.place),
                if (event.address != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 48, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        event.address!,
                        style: const TextStyle(
                          color: MarathonStyle.secondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                _row('접수', event.registrationPeriod ?? '미정'),
              ],
            ),
          ),
          if (event.prices.isNotEmpty) ...[
            const SizedBox(height: 28),
            _heading('참가비'),
            const SizedBox(height: 8),
            for (final price in event.prices.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    SizedBox(
                      child: Text(
                        price.key,
                        style: const TextStyle(
                          color: MarathonStyle.secondary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      price.value is num
                          ? '${_amount(price.value as num)}원'
                          : '${price.value}',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (event.description != null) ...[
            const SizedBox(height: 28),
            _heading('대회 소개'),
            const SizedBox(height: 12),
            Text(
              event.description!,
              style: const TextStyle(
                color: MarathonStyle.secondary,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.65,
              ),
            ),
          ],
          if (event.field('hosts', 'organizer') != null ||
              event.field('hosts', 'phone') != null) ...[
            const SizedBox(height: 28),
            if (event.field('hosts', 'organizer') != null)
              _row('주최', event.field('hosts', 'organizer')!),
            if (event.field('hosts', 'phone') != null)
              _row('문의', event.field('hosts', 'phone')!),
          ],
          const SizedBox(height: 28),
          const Text(
            '일정·접수 여부는 공식 사이트에서 확인해 주세요.',
            style: TextStyle(
              color: MarathonStyle.secondary,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '정보 제공 APIZOA',
            style: TextStyle(color: MarathonStyle.secondary, fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _heading(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.ink,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              color: MarathonStyle.secondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _openWebsite(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await launchUrl(
        event.website!,
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // 링크 열기 실패는 현재 화면에서 안내합니다.
    }
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('대회 사이트를 열지 못했습니다.')),
      );
    }
  }

  String _amount(num value) => value
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}
