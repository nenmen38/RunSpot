import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../data/progress_service.dart';
import '../models/run_progress.dart';
import 'level_progress_bar.dart';

/// 러닝 종료 결과에 표시하는 경험치 보상입니다.
/// 보상은 서버 저장 시 이미 확정되므로 실패하면 조회만 다시 시도합니다.
class RunRewardSection extends StatefulWidget {
  const RunRewardSection({
    required this.service,
    required this.runId,
    this.pendingSync = false,
    this.timeout = const Duration(seconds: 15),
    super.key,
  });
  final ProgressService service;
  final String runId;
  final bool pendingSync;
  final Duration timeout;

  @override
  State<RunRewardSection> createState() => _RunRewardSectionState();
}

class _RunRewardSectionState extends State<RunRewardSection> {
  RunReward? _reward;
  bool _loaded = false;
  bool _loading = false;
  bool _failed = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.pendingSync) unawaited(_load());
  }

  @override
  void didUpdateWidget(RunRewardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runId != widget.runId ||
        oldWidget.service != widget.service ||
        oldWidget.pendingSync != widget.pendingSync) {
      _epoch++;
      _reward = null;
      _loaded = false;
      _loading = false;
      _failed = false;
      if (!widget.pendingSync) unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    final epoch = ++_epoch;
    final service = widget.service;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final reward = await service
          .loadReward(widget.runId)
          .timeout(widget.timeout);
      if (!mounted || epoch != _epoch || !service.isCurrentOwner) return;
      setState(() {
        _reward = reward;
        _loaded = true;
      });
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (widget.pendingSync) {
      child = const _Notice(
        icon: Icons.cloud_upload_outlined,
        text: '서버에 저장되면 경험치가 지급돼요.',
      );
    } else if (_loading) {
      child = const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Expanded(child: Text('보상 확인 중')),
        ],
      );
    } else if (_failed) {
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Notice(
            icon: Icons.error_outline,
            color: AppColors.red,
            text: '보상을 확인하지 못했습니다.\n기록은 저장되었으니 다시 시도해 주세요.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('보상 다시 확인'),
          ),
        ],
      );
    } else if (_loaded && _reward == null) {
      child = const _Notice(
        icon: Icons.info_outline,
        text: '이 기록은 경험치 지급 대상이 아니에요.',
      );
    } else if (_reward != null) {
      child = _RewardResult(reward: _reward!);
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text('러닝 보상', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _RewardResult extends StatelessWidget {
  const _RewardResult({required this.reward});
  final RunReward reward;

  @override
  Widget build(BuildContext context) {
    final progress = reward.progress;
    // 레벨이 오르면 새 레벨 구간을 0부터 채우고, 아니면 획득 전 위치부터 채웁니다.
    final before = reward.leveledUp || progress.isMaxLevel
        ? 0.0
        : ((progress.levelXp - reward.xp).clamp(0, progress.nextLevelXp!) /
                  progress.nextLevelXp!)
              .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reward.leveledUp) ...[
          _LevelUpBanner(from: reward.levelBefore, to: reward.levelAfter),
          const SizedBox(height: 12),
        ],
        Text(
          '+${reward.xp} XP',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.blue,
          ),
        ),
        if (reward.reasonMessage != null) ...[
          const SizedBox(height: 4),
          Text(
            reward.reasonMessage!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.gray),
          ),
        ],
        const SizedBox(height: 10),
        LevelProgressBar(progress: progress, from: before),
      ],
    );
  }
}

class _LevelUpBanner extends StatelessWidget {
  const _LevelUpBanner({required this.from, required this.to});
  final int from;
  final int to;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: .6, end: 1),
    duration: const Duration(milliseconds: 500),
    curve: Curves.elasticOut,
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.blue, AppColors.purple],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '레벨 업!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Lv.$from → Lv.$to ${levelTitle(to)}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    this.color = AppColors.gray,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: TextStyle(color: color)),
      ),
    ],
  );
}
