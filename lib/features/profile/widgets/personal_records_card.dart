import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/account_query_panel.dart';
import '../../../shared/widgets/panel.dart';
import '../data/personal_records_service.dart';

/// 프로필의 개인 최고 기록(1km·5km·10km)입니다. 최근 7일 안에 세운 기록에는 '신기록'을 붙입니다.
class PersonalRecordsCard extends StatelessWidget {
  const PersonalRecordsCard({required this.service, this.now, super.key});

  final PersonalRecordsService service;
  final DateTime Function()? now;

  static const distances = [1, 5, 10];

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_outlined, color: AppColors.orange),
            const SizedBox(width: 8),
            Text('개인 최고 기록', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        AccountQueryPanel<List<PersonalRecord>>(
          source: service,
          load: service.load,
          isCurrentOwner: () => service.isCurrentOwner,
          errorMessage: '최고 기록을 불러오지 못했습니다.',
          builder: (context, records) {
            final current = (now ?? DateTime.now)();
            return Row(
              children: [
                for (final (index, km) in distances.indexed) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _RecordTile(
                      kilometers: km,
                      record: records
                          .where((record) => record.kilometers == km)
                          .firstOrNull,
                      now: current,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.kilometers,
    required this.record,
    required this.now,
  });

  final int kilometers;
  final PersonalRecord? record;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final record = this.record;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Text('${kilometers}km', style: text.labelLarge),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              record == null ? '—' : formatRunDuration(record.duration),
              style: text.titleMedium?.copyWith(fontSize: 18),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            record == null ? '기록 없음' : '${formatPaceDuration(record.pace)}/km',
            style: text.bodySmall?.copyWith(color: AppColors.gray),
          ),
          if (record != null && record.isRecent(now)) ...[
            const SizedBox(height: 6),
            const _NewBadge(),
          ],
        ],
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.orange,
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        '신기록',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

/// 러닝 완료 창에 보여주는 '신기록!' 안내입니다. 이번 러닝이 최고 기록이면 나타납니다.
class NewRecordBanner extends StatefulWidget {
  const NewRecordBanner({
    required this.service,
    required this.runId,
    super.key,
  });

  final PersonalRecordsService service;
  final String runId;

  @override
  State<NewRecordBanner> createState() => _NewRecordBannerState();
}

class _NewRecordBannerState extends State<NewRecordBanner> {
  List<int> _distances = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final records = await widget.service.load();
      if (!mounted || !widget.service.isCurrentOwner) return;
      setState(
        () => _distances = [
          for (final record in records)
            if (record.runId == widget.runId) record.kilometers,
        ],
      );
    } catch (_) {
      // 최고 기록을 확인하지 못해도 완료 화면은 그대로 보여줍니다.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_distances.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: AppColors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_distances.map((km) => '${km}km').join('·')} 신기록!',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: AppColors.orange),
            ),
          ),
        ],
      ),
    );
  }
}
