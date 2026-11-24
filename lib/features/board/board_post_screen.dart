import 'models/course_notes.dart';
import '../../shared/widgets/skeleton.dart';

import 'package:runquest/features/titles/badge_directory.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

import 'board_comments_controller.dart';
import 'widgets/board_user_interaction.dart';
import 'board_compose_screen.dart';
import 'board_controller.dart';
import 'data/board_photo_service.dart';
import 'models/board_post.dart';
import 'widgets/board_theme.dart';
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

  // 좋아요를 반영하는 중인 댓글입니다.
  final _likingComments = <String>{};

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

  Future<void> _openUser({String? commentId}) async {
    final blocked = await showBoardUserInteraction(
      context,
      service: widget.controller.service,
      postId: widget.post.id,
      commentId: commentId,
    );
    if (!mounted || !blocked) return;
    await widget.controller.refresh();
    if (!mounted) return;
    if (commentId == null) {
      Navigator.of(context).pop();
    } else {
      await _comments.refresh();
    }
  }

  void _show(String? message) {
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => BoardTheme(
          child: AlertDialog(
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

  Future<void> _toggleCommentLike(BoardComment comment) async {
    setState(() => _likingComments.add(comment.id));
    final error = await _comments.setLike(comment);
    if (!mounted) return;
    setState(() => _likingComments.remove(comment.id));
    _show(error);
  }

  void _startReply(BoardComment comment) {
    setState(() => _replyTo = comment);
    _inputFocus.requestFocus();
  }

  Future<void> _reportComment(BoardComment comment) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const BoardReportDialog(isComment: true),
    );
    if (!mounted || reason == null) return;
    _show(await _comments.report(comment, reason) ?? '신고가 접수되었습니다.');
  }

  Future<void> _deleteComment(BoardComment comment) async {
    if (!await _confirm('댓글을 삭제할까요?') || !mounted) return;
    _show(await _comments.delete(comment));
  }

  @override
  Widget build(BuildContext context) => BoardTheme(
    child: ListenableBuilder(
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      ..._postBody(context, post),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // 좋아요를 누르면 빨간 하트와 옅은 빨간 바탕으로 바뀝니다.
                          OutlinedButton.icon(
                            onPressed: _liking ? null : _toggleLike,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              shape: const StadiumBorder(),
                              backgroundColor: post.liked
                                  ? AppColors.red.withValues(alpha: .1)
                                  : null,
                              side: BorderSide(
                                color: post.liked
                                    ? AppColors.red.withValues(alpha: .4)
                                    : BoardStyle.line,
                              ),
                              foregroundColor: post.liked
                                  ? AppColors.red
                                  : BoardStyle.ink,
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            icon: Icon(
                              post.liked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: post.liked
                                  ? AppColors.red
                                  : BoardStyle.secondary,
                              size: 18,
                            ),
                            label: Text('좋아요 ${post.likeCount}'),
                          ),
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: ShapeDecoration(
                              shape: StadiumBorder(
                                side: BorderSide(color: BoardStyle.line),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 17,
                                  color: BoardStyle.secondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '댓글 ${post.commentCount}',
                                  style: TextStyle(
                                    color: BoardStyle.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // 글과 댓글 사이는 굵은 띠로 나눕니다.
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: BoardStyle.surface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 4),
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
    ),
  );

  List<Widget> _postBody(BuildContext context, BoardPost post) {
    final raceDate = post.raceDate;
    final raceUrl = post.raceUrl == null ? null : Uri.tryParse(post.raceUrl!);
    return [
      if (post.topic case final topic?) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: BoardTopicChip(topic: topic),
        ),
        const SizedBox(height: 10),
      ],
      SelectableText(
        post.title,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontSize: 22, fontWeight: FontWeight.w800, height: 1.35),
      ),
      const SizedBox(height: 16),
      // 글쓴이: 첫 글자 동그라미·이름·칭호·크루, 아래 줄에 지역과 시각입니다.
      InkWell(
        onTap: post.isMine ? null : () => _openUser(),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            BoardAuthorAvatar(
              nickname: post.nickname,
              postId: post.id,
              size: 40,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListenableBuilder(
                    listenable: BadgeDirectory.instance,
                    builder: (context, _) => Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: post.nickname),
                          // 칭호가 있을 때만 이름 옆에 붙입니다.
                          if (BadgeDirectory.instance.post(post.id)?.title !=
                              null)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: PostAuthorTitle(postId: post.id),
                            ),
                          if (post.crew case final crew?)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: BoardCrewBadge(crew: crew),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: BoardStyle.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (post.region != null) post.region!,
                      formatBoardDateTime(post.createdAt),
                      if (post.isEdited) '수정됨',
                    ].join(' · '),
                    style: BoardStyle.meta,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (raceDate != null)
        Container(
          margin: const EdgeInsets.only(top: 18),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: BoardStyle.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.event_outlined,
                text: formatRaceDate(raceDate),
                trailing: raceCountdown(raceDate),
              ),
              _InfoRow(icon: Icons.place_outlined, text: post.racePlace!),
            ],
          ),
        ),
      const SizedBox(height: 20),
      if (post.topic == BoardTopic.course)
        _CourseDetails(notes: CourseNotes.parse(post.body))
      else
        SelectableText(
          post.body,
          style: BoardStyle.body.copyWith(height: 1.75),
        ),
      for (final url in post.visibleImageUrls) ...[
        const SizedBox(height: 14),
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
        FilledButton.tonalIcon(
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
      return const [SkeletonList(count: 3)];
    }
    if (_comments.error != null) {
      return [
        Text(_comments.error!, style: const TextStyle(color: BoardStyle.error)),
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 30,
                color: BoardStyle.secondary.withValues(alpha: .6),
              ),
              const SizedBox(height: 10),
              Text(
                _comments.canWrite ? '첫 댓글을 남겨 보세요.' : '아직 댓글이 없어요.',
                style: BoardStyle.meta.copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final (:comment, :isReply) in _comments.threads)
        Container(
          // 답글은 들여쓰고 옅은 바탕에 담아 원댓글과 구분합니다.
          margin: EdgeInsets.only(
            left: isReply ? 28 : 0,
            top: isReply ? 4 : 12,
          ),
          padding: EdgeInsets.fromLTRB(isReply ? 12 : 0, 10, 0, 2),
          decoration: isReply
              ? BoxDecoration(
                  color: BoardStyle.surface,
                  borderRadius: BorderRadius.circular(14),
                )
              : null,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isReply)
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 8),
                  child: Icon(
                    Icons.subdirectory_arrow_right,
                    size: 14,
                    color: BoardStyle.secondary,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 2),
                child: BoardAuthorAvatar(
                  nickname: comment.nickname,
                  commentId: comment.id,
                  size: isReply ? 28 : 32,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: comment.isMine
                          ? null
                          : () => _openUser(commentId: comment.id),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: comment.nickname,
                              style: TextStyle(
                                color: BoardStyle.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(
                              text:
                                  '  ${formatBoardDateTime(comment.createdAt)}',
                            ),
                          ],
                        ),
                        style: TextStyle(
                          color: BoardStyle.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      comment.body,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.6,
                      ),
                    ),
                    Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (_comments.canWrite)
                          _CommentAction(
                            label: '답글 달기',
                            onTap: _comments.busy
                                ? null
                                : () => _startReply(comment),
                          ),
                        if (!comment.isMine)
                          PopupMenuButton<String>(
                            tooltip: '댓글 메뉴',
                            enabled: !_comments.busy,
                            icon: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: BoardStyle.secondary,
                            ),
                            onSelected: (_) => _reportComment(comment),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'report',
                                child: Text('신고'),
                              ),
                            ],
                          ),
                        if (comment.isMine || _comments.canModerate)
                          _CommentAction(
                            label: '삭제',
                            onTap: _comments.busy
                                ? null
                                : () => _deleteComment(comment),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // 댓글·답글 오른쪽 끝의 좋아요입니다. 누르면 빨간 하트로 바뀝니다.
              Column(
                children: [
                  IconButton(
                    tooltip: comment.liked ? '댓글 좋아요 취소' : '댓글 좋아요',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed:
                        _comments.canWrite &&
                            !_likingComments.contains(comment.id)
                        ? () => _toggleCommentLike(comment)
                        : null,
                    icon: Icon(
                      comment.liked ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: comment.liked
                          ? AppColors.red
                          : BoardStyle.secondary,
                    ),
                  ),
                  if (comment.likeCount > 0)
                    Text(
                      '${comment.likeCount}',
                      style: TextStyle(
                        color: BoardStyle.secondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  Widget _commentInput(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                    isDense: true,
                    filled: true,
                    fillColor: BoardStyle.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: BoardStyle.accent,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: '댓글 등록',
                style: IconButton.styleFrom(
                  backgroundColor: BoardStyle.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: _comments.busy ? null : _sendComment,
                icon: _comments.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _CommentAction extends StatelessWidget {
  const _CommentAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: BoardStyle.secondary,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
    child: Text(label),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.trailing});

  final IconData icon;
  final String text;

  /// 오른쪽 끝에 붙이는 강조 표시(대회 D-day)입니다.
  final String? trailing;

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
        if (trailing case final label?)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    ),
  );
}

class _CourseDetails extends StatelessWidget {
  const _CourseDetails({required this.notes});
  final CourseNotes notes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (notes.values.isNotEmpty) ...[
        Text('코스 이용 정보', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final entry in notes.values.entries)
          SelectableText(
            '${entry.key} · ${entry.value}',
            style: BoardStyle.body,
          ),
        const SizedBox(height: 12),
      ],
      SelectableText(notes.body, style: BoardStyle.body.copyWith(height: 1.75)),
    ],
  );
}
