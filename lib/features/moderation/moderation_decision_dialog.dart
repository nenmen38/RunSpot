import 'package:flutter/material.dart';

const moderationLabels = {
  'dismissed': '문제없음',
  'warning': '경고',
  'day': '24시간 작성 제한',
  'week': '7일 작성 제한',
  'indefinite': '무기한 작성 제한',
};

typedef ModerationDecision = ({String decision, String note});

class ModerationDecisionDialog extends StatefulWidget {
  const ModerationDecisionDialog({
    required this.nickname,
    required this.kind,
    super.key,
  });
  final String nickname;
  final String kind;

  @override
  State<ModerationDecisionDialog> createState() =>
      _ModerationDecisionDialogState();
}

class _ModerationDecisionDialogState extends State<ModerationDecisionDialog> {
  String? _decision;
  String _note = '';

  String get _effect {
    if (_decision == 'dismissed') {
      return '이 신고를 종결합니다. 콘텐츠와 계정에는 조치가 적용되지 않습니다.';
    }
    final content = switch (widget.kind) {
      'avatar' => '신고 당시 사진이 현재 프로필에 남아 있으면 삭제합니다.',
      'meetup' => '신고된 모임 모집을 취소합니다.',
      _ => '신고된 콘텐츠를 삭제합니다.',
    };
    return _decision == 'warning'
        ? '$content 사용자에게 경고를 기록합니다.'
        : '$content 게시글·댓글·채팅 작성과 모임 모집을 제한합니다.';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    actionsOverflowAlignment: OverflowBarAlignment.end,
    actionsOverflowButtonSpacing: 8,
    title: const Text('신고 대상자 조치'),
    content: SizedBox(
      width: 400,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '신고 대상 · ${widget.nickname}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            isExpanded: true,
            decoration: const InputDecoration(labelText: '처리 방법'),
            hint: const Text('조치 선택'),
            items: [
              for (final entry in moderationLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => setState(() => _decision = value),
          ),
          if (_decision != null) ...[const SizedBox(height: 12), Text(_effect)],
          const SizedBox(height: 16),
          TextField(
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: '처리 사유 (필수)',
              helperText: _decision == null || _decision == 'dismissed'
                  ? null
                  : '알림에 표시할 위반 사유를 적어 주세요. 예를 들어 다른 이용자 비하처럼 적고, 신고자 정보는 제외해 주세요.',
              helperMaxLines: 3,
            ),
            onChanged: (value) => setState(() => _note = value.trim()),
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
        onPressed: _decision == null || _note.isEmpty
            ? null
            : () => Navigator.pop(context, (decision: _decision!, note: _note)),
        child: const Text('처리 확정'),
      ),
    ],
  );
}
