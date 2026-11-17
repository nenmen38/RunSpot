import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 화면 전체(또는 목록 자리)에 보여주는 로딩·빈 화면·오류 안내입니다. 모든 화면이 같은 모양을 씁니다.
/// - 로딩: 가운데 원형 표시와 선택 문구
/// - 빈 화면: 둥근 아이콘·안내 문구·선택 버튼
/// - 오류: 연결 문제 아이콘·안내 문구·'다시 시도' 버튼
class StatusView extends StatelessWidget {
  const StatusView.loading({this.message, super.key})
    : icon = null,
      actionLabel = null,
      onAction = null,
      _kind = _StatusKind.loading;

  const StatusView.empty({
    required String this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : _kind = _StatusKind.empty;

  const StatusView.error({
    required String this.message,
    VoidCallback? onRetry,
    this.icon = Icons.cloud_off_outlined,
    super.key,
  }) : actionLabel = onRetry == null ? null : '다시 시도',
       onAction = onRetry,
       _kind = _StatusKind.error;

  final String? message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final _StatusKind _kind;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final message = this.message;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_kind == _StatusKind.loading)
              const SizedBox.square(
                dimension: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              CircleAvatar(
                radius: 28,
                backgroundColor: _kind == _StatusKind.error
                    ? AppColors.red.withValues(alpha: .12)
                    : AppColors.blueSoft,
                foregroundColor: _kind == _StatusKind.error
                    ? AppColors.red
                    : AppColors.blueText,
                child: Icon(icon, size: 28),
              ),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: AppColors.gray),
              ),
            ],
            if (actionLabel case final label?) ...[
              const SizedBox(height: 14),
              _kind == _StatusKind.error
                  ? OutlinedButton.icon(
                      onPressed: onAction,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(label),
                    )
                  : FilledButton(onPressed: onAction, child: Text(label)),
            ],
          ],
        ),
      ),
    );
  }
}

enum _StatusKind { loading, empty, error }

/// 카드·패널 안처럼 좁은 자리에 쓰는 한 줄짜리 오류 안내입니다.
class InlineError extends StatelessWidget {
  const InlineError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.error_outline, size: 18, color: AppColors.red),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.gray),
        ),
      ),
    ],
  );
}
