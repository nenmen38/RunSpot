import 'package:flutter/material.dart';

import '../moderation/moderation_screen.dart';
import '../run_history/widgets/run_splits_panel.dart';
import '../run_history/widgets/run_motion_evidence_panel.dart';

import '../../shared/widgets/account_query_panel.dart';
import 'data/review_service.dart';
import 'widgets/staff_mfa_control.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({this.service, super.key});
  final ReviewService? service;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _revision = 0;
  bool _busy = false;

  Future<void> _resolve(IntegrityReview item, bool approved) async {
    final service = widget.service!;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ReviewDecisionDialog(approved: approved),
    );
    if (!mounted || value == null || !service.isCurrentOwner) return;
    setState(() => _busy = true);
    try {
      await service.resolve(item.id, approved: approved, note: value);
    } catch (_) {
      if (mounted && service.isCurrentOwner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('처리하지 못했습니다. 권한과 최신 검토 상태를 확인해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _revision++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    return ListView(
      children: [
        if (service is SupabaseReviewService)
          StaffMfaControl(
            client: service.client,
            isCurrentOwner: () => service.isCurrentOwner,
            onVerified: () => setState(() => _revision++),
          ),
        if (service is SupabaseReviewService) ...[
          Text('커뮤니티 관리', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (mode, label, hint, icon) in const [
                  (
                    'cases',
                    '통합 신고 관리',
                    '신고 증거 검토 및 사용자 조치',
                    Icons.flag_outlined,
                  ),
                  ('appeals', '이의신청 관리', '접수된 이의신청 검토', Icons.forum_outlined),
                  ('history', '전체 위반 이력', '사용자별 경고 및 작성 제한 내역', Icons.history),
                ]) ...[
                  if (mode != 'cases') const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(
                      icon,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(label),
                    subtitle: Text(hint),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ModerationScreen(
                          service: ModerationService(service.client),
                          mode: mode,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
        Text('러닝 기록 검토', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (service != null)
          AccountQueryPanel<List<IntegrityReview>>(
            source: service,
            load: service.load,
            isCurrentOwner: () => service.isCurrentOwner,
            revision: _revision,
            errorMessage: '검토 목록을 조회할 수 없습니다. 관리자 권한과 다중 인증을 확인해 주세요.',
            builder: (context, items) => Column(
              children: [
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('검토할 기록이 없습니다.'),
                  ),
                for (final item in items)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.nickname,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(item.distance / 1000).toStringAsFixed(2)}km · ${item.seconds}초 · 위험도 ${item.risk}',
                          ),
                          Text(
                            item.rule == 'sustained_speed_over_6_5'
                                ? '지속 속도 초과'
                                : item.rule == 'split_speed_over_6_5'
                                ? '구간 속도 초과'
                                : '평균 속도 초과',
                          ),
                          if (item.motionEvidence?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: RunMotionEvidencePanel(
                                evidence: item.motionEvidence!,
                                showAccuracy: true,
                              ),
                            ),
                          if (item.splits?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: RunSplitsPanel(
                                splits: item.splits,
                                motionEvidence: const [],
                              ),
                            ),
                          const SizedBox(height: 12),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            overflowAlignment: OverflowBarAlignment.end,
                            spacing: 8,
                            overflowSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _resolve(item, true),
                                child: const Text('승인'),
                              ),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => _resolve(item, false),
                                child: const Text('반려'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          const Text('관리 기능에 연결할 수 없습니다.'),
      ],
    );
  }
}

class _ReviewDecisionDialog extends StatefulWidget {
  const _ReviewDecisionDialog({required this.approved});
  final bool approved;
  @override
  State<_ReviewDecisionDialog> createState() => _ReviewDecisionDialogState();
}

class _ReviewDecisionDialogState extends State<_ReviewDecisionDialog> {
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.approved ? '기록 승인' : '기록 반려'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.approved
                ? '승인해도 기존 경험치 지급 기준은 유지됩니다.'
                : '개인 기록은 보존하며 친구 랭킹·업적·현재 경험치에서 제외합니다.',
          ),
          TextField(
            controller: _note,
            maxLength: 2000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '처리 사유'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (_note.text.trim().isNotEmpty) {
            Navigator.pop(context, _note.text.trim());
          }
        },
        child: const Text('확정'),
      ),
    ],
  );
}
