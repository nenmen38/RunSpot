import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/badge_pill.dart';
import 'package:url_launcher/url_launcher.dart';

import 'board_comments_controller.dart';
import 'board_compose_screen.dart';
import 'board_controller.dart';
import 'data/board_photo_service.dart';
import 'models/board_post.dart';
import 'widgets/board_photo.dart';
import 'widgets/board_post_tile.dart';
import 'widgets/board_report_dialog.dart';

class BoardPostScreen extends StatefulWidget {
  const BoardPostScreen({
    required this.post,
    required this.controller,
    this.photoService,
    super.key,
  });

  final BoardPost post;
  final BoardController controller;

  /// 없으면 기기 갤러리에서 사진을 고릅니다.
  final BoardPhotoService? photoService;

  @override
  State<BoardPostScreen> createState() => _BoardPostScreenState();
}

class _BoardPostScreenState extends State<BoardPostScreen> {
  late final _comments = BoardCommentsController(
    widget.controller.service,
    widget.post.id,
    onCount: (count) =>
        widget.controller.updateCommentCount(widget.post.id, count),
  );
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  bool _liking = false;

  // 답글을 쓰는 중이면 대상 댓글입니다.
  BoardComment? _replyTo;

  // 수정·좋아요 뒤에는 목록 컨트롤러의 최신 글을 보여줍니다.
  BoardPost get _post =>
      widget.controller.postById(widget.post.id) ?? widget.post;

  @override
  void initState() {
    super.initState();
    unawaited(_comments.refresh());
  }

  @override
  void dispose() {
    _comments.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _show(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text('삭제하면 되돌릴 수 없어요.'),
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
      ) ==
      true;

  Future<void> _delete() async {
    if (!await _confirm('글을 삭제할까요?') || !mounted) return;
    final error = await widget.controller.delete(_post);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      _show(error);
    }
  }

  Future<void> _edit() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BoardComposeScreen(
          controller: widget.controller,
          photoService: widget.photoService,
          post: _post,
        ),
      ),
    );
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const BoardReportDialog(),
    );
    if (reason == null || !mounted) return;
    _show(await widget.controller.report(_post, reason) ?? '신고가 접수되었습니다.');
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);
    final error = await widget.controller.setLike(_post, !_post.liked);
    if (mounted) setState(() => _liking = false);
    _show(error);
  }

  Future<void> _sendComment() async {
    final error = await _comments.add(_input.text, parent: _replyTo);
    if (!mounted) return;
    if (error == null) {
      _input.clear();
      setState(() => _replyTo = null);
      FocusScope.of(context).unfocus();
    } else {
      _show(error);
    }
  }

  void _startReply(BoardComment comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  Future<void> _deleteComment(BoardComment comment) async {
    if (!await _confirm('댓글을 삭제할까요?') || !mounted) return;
    _show(await _comments.delete(comment));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.controller, _comments]),
    builder: (context, _) {
      final post = _post;
      final canEdit =
          post.isMine &&
          (post.kind != BoardKind.race || widget.controller.canPostRace);
      return Scaffold(
        appBar: AppBar(
          title: Text(post.kind.label),
          actions: [
            PopupMenuButton<String>(
              tooltip: '게시글 메뉴',
              enabled: !widget.controller.busy,
              onSelected: (value) => switch (value) {
                'edit' => _edit(),
                'report' => _report(),
                _ => _delete(),
              },
              itemBuilder: (_) => [
                if (canEdit)
                  const PopupMenuItem(value: 'edit', child: Text('수정')),
                if (!post.isMine)
                  const PopupMenuItem(value: 'report', child: Text('신고')),
                if (post.isMine || widget.controller.canModerate)
                  const PopupMenuItem(value: 'delete', child: Text('삭제')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _comments.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                  children: [
                    ..._postBody(context, post),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _liking ? null : _toggleLike,
                          icon: Icon(
                            post.liked ? Icons.favorite : Icons.favorite_border,
                            color: post.liked ? AppColors.red : null,
                            size: 18,
                          ),
                          label: Text('좋아요 ${post.likeCount}'),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: AppColors.gray,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '댓글 ${post.commentCount}',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    ..._commentList(context),
                  ],
                ),
              ),
            ),
            if (_comments.canWrite) _commentInput(context),
          ],
        ),
      );
    },
  );

  List<Widget> _postBody(BuildContext context, BoardPost post) {
    final raceDate = post.raceDate;
    final raceUrl = post.raceUrl == null ? null : Uri.tryParse(post.raceUrl!);
    return [
      if (post.topic != null) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: BadgePill(text: post.topic!.label),
        ),
        const SizedBox(height: 8),
      ],
      SelectableText(post.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        [
          post.nickname,
          if (post.region != null) post.region!,
          formatBoardDateTime(post.createdAt),
          if (post.isEdited) '수정됨',
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
        style: const TextStyle(color: AppColors.ink, fontSize: 14, height: 1.5),
      ),
      for (final url in post.visibleImageUrls) ...[
        const SizedBox(height: 12),
        BoardPhoto(url: url),
      ],
      if (post.images.length > post.visibleImageUrls.length)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '사진 일부를 불러오지 못했어요. 목록을 새로고침해 주세요.',
            style: Theme.of(context).textTheme.bodyMedium,
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
    ];
  }

  List<Widget> _commentList(BuildContext context) {
    if (_comments.loading && !_comments.loaded) {
      return const [Center(child: CircularProgressIndicator())];
    }
    if (_comments.error != null) {
      return [
        Text(_comments.error!, style: const TextStyle(color: AppColors.red)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _comments.refresh,
            child: const Text('다시 시도'),
          ),
        ),
      ];
    }
    if (_comments.comments.isEmpty) {
      return [
        Text(
          _comments.canWrite ? '첫 댓글을 남겨 보세요.' : '아직 댓글이 없어요.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ];
    }
    return [
      for (final (:comment, :isReply) in _comments.threads)
        Padding(
          padding: EdgeInsets.only(left: isReply ? 22 : 0, top: 6, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isReply)
                const Padding(
                  padding: EdgeInsets.only(right: 4, top: 1),
                  child: Icon(
                    Icons.subdirectory_arrow_right,
                    size: 14,
                    color: AppColors.gray,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${comment.nickname} · ${formatBoardDateTime(comment.createdAt)}',
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      comment.body,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                      ),
                    ),
                    if (_comments.canWrite)
                      GestureDetector(
                        onTap: _comments.busy
                            ? null
                            : () => _startReply(comment),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '답글 달기',
                            style: TextStyle(
                              color: AppColors.gray,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (comment.isMine || _comments.canModerate)
                IconButton(
                  tooltip: '댓글 삭제',
                  visualDensity: VisualDensity.compact,
                  onPressed: _comments.busy
                      ? null
                      : () => _deleteComment(comment),
                  icon: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _commentInput(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo case final target?)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${target.nickname}님에게 답글 작성 중',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: '답글 취소',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _replyTo = null),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          Row(
            children: [
              Expanded(
                // 기기 키보드의 이모티콘을 그대로 입력할 수 있습니다.
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  maxLength: 500,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _replyTo == null ? '댓글을 입력해 주세요' : '답글을 입력해 주세요',
                    counterText: '',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                tooltip: '댓글 등록',
                onPressed: _comments.busy ? null : _sendComment,
                icon: _comments.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: AppColors.blue),
              ),
            ],
          ),
        ],
      ),
    ),
  );
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
