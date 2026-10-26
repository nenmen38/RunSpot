import 'package:flutter/material.dart';

import '../../../shared/widgets/account_query_panel.dart';
import '../data/review_service.dart';

class BoardReportsPanel extends StatefulWidget {
  const BoardReportsPanel({required this.service, super.key});
  final SupabaseReviewService service;
  @override
  State<BoardReportsPanel> createState() => _BoardReportsPanelState();
}

class _BoardReportsPanelState extends State<BoardReportsPanel> {
  int _revision = 0;
  bool _busy = false;
  Future<void> _resolve(Map<String, dynamic> report, String decision) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _ReportDecisionDialog(remove: decision == 'removed'),
    );
    if (note == null || !mounted || !widget.service.isCurrentOwner) return;
    setState(() => _busy = true);
    try {
      await widget.service.resolveBoardReport(
        report['id'] as String,
        decision,
        note,
      );
    } catch (_) {
      if (mounted && widget.service.isCurrentOwner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('처리하지 못했습니다. 권한과 최신 상태를 확인해 주세요.')),
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 32),
      Text('게시글 신고', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      AccountQueryPanel<List<Map<String, dynamic>>>(
        source: widget.service,
        load: widget.service.loadBoardReports,
        isCurrentOwner: () => widget.service.isCurrentOwner,
        revision: _revision,
        errorMessage: '신고 목록을 조회할 수 없습니다. 관리자 다중 인증을 확인해 주세요.',
        builder: (context, reports) => Column(
          children: [
            if (reports.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('접수된 신고가 없습니다.'),
              ),
            for (final report in reports)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        report['title'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(report['nickname'] as String),
                      const SizedBox(height: 8),
                      Text(report['body'] as String),
                      const Divider(height: 24),
                      Text('신고 사유: ${report['reason']}'),
                      if (report['is_mine'] == true)
                        const Text('본인 게시글은 다른 관리자가 처리해야 합니다.')
                      else
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _resolve(report, 'dismissed'),
                              child: const Text('문제없음'),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _resolve(report, 'removed'),
                              child: const Text('게시글 삭제'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _ReportDecisionDialog extends StatefulWidget {
  const _ReportDecisionDialog({required this.remove});
  final bool remove;
  @override
  State<_ReportDecisionDialog> createState() => _ReportDecisionDialogState();
}

class _ReportDecisionDialogState extends State<_ReportDecisionDialog> {
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.remove ? '게시글을 삭제할까요?' : '신고를 종결할까요?'),
    content: TextField(
      controller: _note,
      minLines: 2,
      maxLines: 4,
      maxLength: 500,
      decoration: const InputDecoration(hintText: '처리 사유'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _note.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, _note.text.trim()),
        child: Text(widget.remove ? '삭제' : '종결'),
      ),
    ],
  );
}
