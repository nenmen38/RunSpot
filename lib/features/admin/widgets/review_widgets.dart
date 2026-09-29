import 'package:flutter/material.dart';
import 'package:runquest/features/admin/models/review_case.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/action_button.dart';
import 'package:runquest/shared/widgets/badge_pill.dart';
import 'package:runquest/shared/widgets/page_layout.dart';
import 'package:runquest/shared/widgets/panel.dart';
import 'package:runquest/shared/widgets/stat_card.dart';

class AdminStats extends StatelessWidget {
  const AdminStats({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: StatCard(
            label: '오늘 러닝',
            value: '1,284',
            icon: Icons.directions_run,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '검토 필요',
            value: '17',
            icon: Icons.warning_amber,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: StatCard(
            label: '소명 대기',
            value: '6',
            icon: Icons.outgoing_mail,
          ),
        ),
      ],
    );
  }
}

class AdminReviewCard extends StatelessWidget {
  const AdminReviewCard({
    required this.review,
    required this.onAction,
    super.key,
  });

  final ReviewCase review;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: '이상 기록',
            subtitle: '자동 탐지 후 관리자 검토',
            icon: Icons.admin_panel_settings_outlined,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  review.user,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              BadgePill(text: review.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.reason,
            style: const TextStyle(
              color: AppColors.red,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(review.summary, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: review.risk / 100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                  color: AppColors.red,
                  backgroundColor: AppColors.line,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '위험 ${review.risk}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const Spacer(),
          ActionButton(
            label: '소명 요청 알림 보내기',
            icon: Icons.outgoing_mail,
            onTap: () => onAction('소명 요청'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ActionButton(
                  label: '경고',
                  icon: Icons.warning_amber,
                  onTap: () => onAction('경고'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ActionButton(
                  label: '정지',
                  icon: Icons.pause_circle_outline,
                  onTap: () => onAction('일시 정지'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
