import 'dart:async';

import 'package:flutter/material.dart';

import 'board_controller.dart';
import 'board_post_screen.dart';
import 'data/board_service.dart';
import 'models/board_post.dart';

/// 알림처럼 글 ID만 알 때 글을 불러와 상세 화면을 엽니다.
class BoardPostLoaderScreen extends StatefulWidget {
  const BoardPostLoaderScreen({
    required this.service,
    required this.postId,
    super.key,
  });

  final BoardService service;
  final String postId;

  @override
  State<BoardPostLoaderScreen> createState() => _BoardPostLoaderScreenState();
}

class _BoardPostLoaderScreenState extends State<BoardPostLoaderScreen> {
  late final _controller = BoardController(
    widget.service,
    postId: widget.postId,
  );

  // 처음 불러온 글을 기억해 좋아요·수정 뒤 다시 불러오는 동안에도 화면을 유지합니다.
  BoardPost? _post;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    unawaited(_controller.refresh());
  }

  void _changed() {
    if (_post == null && mounted) {
      setState(() => _post = _controller.postById(widget.postId));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    if (post != null) {
      return BoardPostScreen(post: post, controller: _controller);
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('게시글')),
        body: Center(
          child:
              _controller.loading ||
                  !_controller.loaded && _controller.error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _controller.error ?? '삭제되었거나 볼 수 없는 글입니다.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _controller.refresh,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
