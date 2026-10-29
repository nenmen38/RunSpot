import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'board_compose_screen.dart';
import 'board_controller.dart';
import 'board_post_screen.dart';
import 'data/board_photo_service.dart';
import 'data/board_service.dart';
import 'models/board_post.dart';
import 'widgets/board_theme.dart';
import 'widgets/board_filter_menu.dart';
import 'races/marathon_board.dart';
import 'races/marathon_service.dart';
import 'region_picker_screen.dart';
import 'widgets/board_post_tile.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({
    this.service,
    this.photoService,
    this.marathonService,
    super.key,
  });

  final BoardService? service;
  final BoardPhotoService? photoService;
  final MarathonService? marathonService;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final BoardController _controller = BoardController(
    widget.service ?? SupabaseBoardService(Supabase.instance.client),
  );
  late final BoardPhotoService _photos =
      widget.photoService ?? GalleryBoardPhotoService();
  final _search = TextEditingController();
  bool _searching = false;
  late final MarathonService? _marathons =
      widget.marathonService ??
      (_controller.service is SupabaseBoardService
          ? SupabaseMarathonService(
              (_controller.service as SupabaseBoardService).client,
            )
          : null);

  @override
  void initState() {
    super.initState();
    unawaited(_controller.refresh());
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
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

  /// 동네 말머리를 고르면 동네를 고르고 그 동네 글만 보여줍니다.
  Future<void> _pickLocal() async {
    final region = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RegionPickerScreen(current: _controller.region),
      ),
    );
    if (region == null || !mounted) return;
    _showMessage(await _controller.selectLocal(region));
  }

  void _selectFilter(_NewsFilter? value) {
    if (value == _NewsFilter.local) {
      if (!_controller.busy) unawaited(_pickLocal());
    } else {
      _controller.selectTopic(value?.topic);
    }
  }

  Future<void> _compose() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            BoardComposeScreen(controller: _controller, photoService: _photos),
      ),
    );
  }

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching) {
      _search.clear();
      _controller.search('');
    }
  }

  void _open(BoardPost post) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BoardPostScreen(
          post: post,
          controller: _controller,
          photoService: _photos,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BoardTheme(
    child: ListenableBuilder(
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
                      Text(
                        '게시판',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        _subtitle(controller.kind),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: BoardStyle.meta.copyWith(fontSize: 13),
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
                for (final kind in const [BoardKind.news, BoardKind.race])
                  ButtonSegment(value: kind, label: Text(kind.label)),
              ],
              // 동네 글을 보는 중에도 러닝 소식 탭이 선택된 상태입니다.
              selected: {
                controller.kind == BoardKind.race
                    ? BoardKind.race
                    : BoardKind.news,
              },
              onSelectionChanged: (value) {
                // 게시판을 바꾸면 검색도 새로 시작합니다.
                _search.clear();
                controller.select(value.single);
              },
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
            const SizedBox(height: 4),
            // 모든 게시판에서 조건 선택은 왼쪽, 검색은 오른쪽에 둡니다.
            if (controller.kind != BoardKind.race || _marathons == null)
              Row(
                children: [
                  if (controller.kind != BoardKind.race)
                    BoardFilterMenu<_NewsFilter>(
                      values: _NewsFilter.values,
                      selected: controller.kind == BoardKind.local
                          ? _NewsFilter.local
                          : _NewsFilter.of(controller.topic),
                      labelOf: (filter) => filter.label,
                      onChanged: _selectFilter,
                      tooltip: '말머리 선택',
                    ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('최신순', style: BoardStyle.meta)),
                  IconButton(
                    tooltip: _searching ? '검색 닫기' : '검색',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: _toggleSearch,
                    icon: Icon(_searching ? Icons.search_off : Icons.search),
                  ),
                ],
              ),
            if (_searching) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('board-search'),
                controller: _search,
                autofocus: true,
                maxLength: 50,
                textInputAction: TextInputAction.search,
                onSubmitted: controller.search,
                decoration: InputDecoration(
                  hintText: '${controller.kind.label} 게시판에서 제목·내용 검색',
                  prefixIcon: const Icon(Icons.search),
                  counterText: '',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: '검색',
                    onPressed: () => controller.search(_search.text),
                    icon: const Icon(Icons.arrow_forward),
                  ),
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
    ),
  );

  String _subtitle(BoardKind kind) => switch (kind) {
    BoardKind.local => '우리 동네 러닝 코스·꿀 정보·맛집',
    BoardKind.national || BoardKind.news => '전국과 우리 동네 추천 코스·꿀 정보·맛집',
    BoardKind.race => '전국 러닝 대회 일정',
  };

  Widget _body(BuildContext context, BoardController controller) {
    final marathons = _marathons;
    if (controller.kind == BoardKind.race && marathons != null) {
      return MarathonBoard(
        service: marathons,
        notices: controller.posts,
        onOpenNotice: _open,
        refreshNotices: controller.refresh,
        query: controller.query,
        onSearch: _toggleSearch,
        searching: _searching,
      );
    }
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
                  icon: controller.query == null
                      ? Icons.forum_outlined
                      : Icons.search_off,
                  message: controller.query != null
                      ? "'${controller.query}'이(가) 들어간 글이 없어요."
                      : controller.kind == BoardKind.race
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
            ? const Divider(height: 1, color: BoardStyle.line, thickness: .5)
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

/// 러닝 소식의 말머리입니다. 전국 게시판 말머리에 동네를 더했습니다.
enum _NewsFilter {
  course(BoardTopic.course),
  tip(BoardTopic.tip),
  food(BoardTopic.food),
  local(null);

  const _NewsFilter(this.topic);
  final BoardTopic? topic;

  String get label => topic?.label ?? '동네';

  static _NewsFilter? of(BoardTopic? topic) => values
      .where((filter) => filter.topic != null && filter.topic == topic)
      .firstOrNull;
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
