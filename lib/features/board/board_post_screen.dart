import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/badge_pill.dart';
import 'package:url_launcher/url_launcher.dart';

import 'board_controller.dart';
import 'board_compose_screen.dart';
import 'widgets/board_report_dialog.dart';
import 'models/board_post.dart';
import 'widgets/board_post_tile.dart';

class BoardPostScreen extends StatelessWidget {
  const BoardPostScreen({
    required this.post,
    required this.controller,
    super.key,
  });

  final BoardPost post;
  final BoardController controller;

  Future<void> _edit(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BoardComposeScreen(controller: controller, post: post),
      ),
    );
    if (saved == true && context.mounted) Navigator.pop(context);
  }

  Future<void> _report(BuildContext context) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const BoardReportDialog(),
    );
    if (reason == null || !context.mounted) return;
    final error = await controller.report(post, reason);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error ?? '신고가 접수되었습니다.')));
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('글을 삭제할까요?'),
        content: const Text('삭제한 글은 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await controller.delete(post);
    if (!context.mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final raceDate = post.raceDate;
    final raceUrl = post.raceUrl == null ? null : Uri.tryParse(post.raceUrl!);
    return Scaffold(
      appBar: AppBar(
        title: Text(post.kind.label),
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => PopupMenuButton<String>(
              tooltip: '게시글 메뉴',
              enabled: !controller.busy,
              onSelected: (value) {
                if (value == 'edit') {
                  _edit(context);
                } else if (value == 'report') {
                  _report(context);
                } else {
                  _delete(context);
                }
              },
              itemBuilder: (_) => [
                if (post.isMine)
                  const PopupMenuItem(value: 'edit', child: Text('수정')),
                if (!post.isMine)
                  const PopupMenuItem(value: 'report', child: Text('신고')),
                if (post.isMine || controller.canModerate)
                  const PopupMenuItem(value: 'delete', child: Text('삭제')),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          if (post.topic != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: BadgePill(text: post.topic!.label),
            ),
            const SizedBox(height: 8),
          ],
          SelectableText(
            post.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            [
              post.nickname,
              if (post.region != null) post.region!,
              formatBoardTime(post.createdAt),
            ].join(' · '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (raceDate != null) ...[
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.event_outlined,
              text: '${formatRaceDate(raceDate)} · ${raceCountdown(raceDate)}',
            ),
            _InfoRow(icon: Icons.place_outlined, text: post.racePlace!),
          ],
          const Divider(height: 28),
          SelectableText(
            post.body,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (raceUrl != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => unawaited(
                launchUrl(raceUrl, mode: LaunchMode.externalApplication),
              ),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('대회 안내 페이지 열기'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.blue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.labelLarge),
        ),
      ],
    ),
  );
}
