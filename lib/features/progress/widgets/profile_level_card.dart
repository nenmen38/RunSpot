import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../data/progress_service.dart';
import '../models/run_progress.dart';
import 'level_progress_bar.dart';

/// 프로필의 레벨 칭호와 경험치 진행 바입니다. 화면을 열 때마다 서버 값을 조회합니다.
class ProfileLevelCard extends StatefulWidget {
  const ProfileLevelCard({required this.service, super.key});
  final ProgressService service;

  @override
  State<ProfileLevelCard> createState() => _ProfileLevelCardState();
}

class _ProfileLevelCardState extends State<ProfileLevelCard> {
  RunProgress? _progress;
  bool _failed = false;
  bool _loading = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ProfileLevelCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _progress = null;
      _loading = false;
      unawaited(_load());
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
      final progress = await service.load().timeout(
        const Duration(seconds: 15),
      );
      if (mounted && epoch == _epoch && service.isCurrentOwner) {
        setState(() => _progress = progress);
      }
    } catch (_) {
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${levelTitle(progress.level)} · 누적 ${progress.totalXp} XP',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          LevelProgressBar(progress: progress),
        ],
      );
    }
    if (_failed) {
      return Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('레벨 정보를 불러오지 못했습니다.')),
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        ],
      );
    }
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Text('레벨 확인 중'),
      ],
    );
  }
}
