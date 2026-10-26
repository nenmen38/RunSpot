import 'package:flutter/material.dart';

import '../run_history/widgets/run_splits_panel.dart';
import '../run_history/widgets/run_motion_evidence_panel.dart';

import '../../shared/widgets/account_query_panel.dart';
import 'data/review_service.dart';
import 'widgets/staff_mfa_control.dart';
import 'widgets/board_reports_panel.dart';

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
        Text('관리', style: Theme.of(context).textTheme.titleLarge),
        const Text('확인이 필요한 기록'),
        if (service is SupabaseReviewService)
          StaffMfaControl(
            client: service.client,
            isCurrentOwner: () => service.isCurrentOwner,
            onVerified: () => setState(() => _revision++),
          ),
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
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.nickname),
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
                          Wrap(
                            spacing: 8,
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
        if (service is SupabaseReviewService)
          BoardReportsPanel(key: ValueKey(_revision), service: service),
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
