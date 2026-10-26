import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'board_compose_screen.dart';
import 'board_controller.dart';
import 'board_post_screen.dart';
import 'data/board_service.dart';
import 'models/board_post.dart';
import 'region_picker_screen.dart';
import 'widgets/board_post_tile.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({this.service, super.key});

  final BoardService? service;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final BoardController _controller = BoardController(
    widget.service ?? SupabaseBoardService(Supabase.instance.client),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_controller.refresh());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickRegion() async {
    final region = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RegionPickerScreen(current: _controller.region),
      ),
    );
    if (region == null || region == _controller.region) return;
    _showMessage(await _controller.changeRegion(region));
  }

  Future<void> _compose() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BoardComposeScreen(controller: _controller),
      ),
    );
  }

  void _open(BoardPost post) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BoardPostScreen(post: post, controller: _controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final controller = _controller;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('게시판', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      _subtitle(controller.kind),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (controller.canCreate)
                FilledButton.icon(
                  onPressed: controller.busy ? null : _compose,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    controller.kind == BoardKind.race ? '공지 등록' : '글쓰기',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<BoardKind>(
            showSelectedIcon: false,
            segments: [
              for (final kind in BoardKind.values)
                ButtonSegment(value: kind, label: Text(kind.label)),
            ],
            selected: {controller.kind},
            onSelectionChanged: (value) => controller.select(value.single),
          ),
          if (controller.kind == BoardKind.local) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.place_outlined,
                  size: 18,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    controller.region ?? '동네를 설정하지 않았어요',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                TextButton(
                  onPressed: controller.busy || !controller.loaded
                      ? null
                      : _pickRegion,
                  child: Text(controller.region == null ? '설정' : '변경'),
                ),
              ],
            ),
          ],
          if (controller.kind != BoardKind.race) ...[
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final topic in <BoardTopic?>[null, ...BoardTopic.values])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(topic?.label ?? '전체'),
                        selected: controller.topic == topic,
                        onSelected: (_) => controller.selectTopic(topic),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (!controller.canWrite &&
              controller.loaded &&
              controller.kind != BoardKind.race)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '이메일 인증과 닉네임 등록을 마치면 글을 쓸 수 있어요.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          Expanded(child: _body(context, controller)),
        ],
      );
    },
  );

  String _subtitle(BoardKind kind) => switch (kind) {
    BoardKind.local => '우리 동네 러닝 코스·꿀 정보·맛집',
    BoardKind.national => '전국 추천 코스·꿀 정보·맛집',
    BoardKind.race => '전국 러닝 대회 일정 공지',
  };

  Widget _body(BuildContext context, BoardController controller) {
    if (controller.loading && controller.posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.needsRegion) {
      return _Notice(
        icon: Icons.home_work_outlined,
        message: '동네를 설정하면 같은 동네 주민들이 올린\n러닝 코스와 맛집을 볼 수 있어요.',
        action: '동네 설정하기',
        onAction: controller.busy ? null : _pickRegion,
      );
    }
    if (controller.error != null && controller.posts.isEmpty) {
      return _Notice(
        icon: Icons.cloud_off_outlined,
        message: controller.error!,
        action: '다시 시도',
        onAction: controller.refresh,
      );
    }
    if (controller.posts.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: _Notice(
                  icon: Icons.forum_outlined,
                  message: controller.kind == BoardKind.race
                      ? '예정된 러닝 대회 공지가 없어요.'
                      : '아직 글이 없어요.\n첫 글을 남겨 보세요.',
                ),
              ),
            ],
          ),
        ),
      );
    }
    final posts = controller.posts;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: posts.length + 1,
        separatorBuilder: (_, index) => index < posts.length - 1
            ? const Divider(height: 1)
            : const SizedBox.shrink(),
        itemBuilder: (context, index) {
          if (index < posts.length) {
            return BoardPostTile(
              post: posts[index],
              onTap: () => _open(posts[index]),
            );
          }
          if (controller.error != null) {
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  Text(
                    controller.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.red),
                  ),
                  TextButton(
                    onPressed: controller.hasMore
                        ? controller.loadMore
                        : controller.refresh,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }
          if (!controller.hasMore) return const SizedBox(height: 8);
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: controller.loadingMore
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: controller.loadMore,
                      child: const Text('더 보기'),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: AppColors.gray),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (action != null) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}
