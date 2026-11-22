import 'package:flutter/material.dart';

/// 말풍선을 오른쪽으로 충분히 밀었다 놓으면 답장을 시작합니다.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    required this.onReply,
    required this.incoming,
    required this.child,
    super.key,
  });

  final VoidCallback onReply;
  final bool incoming;
  final Widget child;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  static const _threshold = 52.0;
  static const _maxOffset = 72.0;
  double _offset = 0;
  bool _dragging = false;

  void _reset() {
    setState(() {
      _offset = 0;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 받은 말풍선 옆의 화살표가 긴 메시지에서도 화면 안에 남도록 이동 폭을 줄입니다.
    final slide = widget.incoming ? _offset / 6 : _offset;
    return GestureDetector(
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (details) => setState(
        () => _offset = (_offset + details.delta.dx).clamp(0.0, _maxOffset),
      ),
      onHorizontalDragCancel: _reset,
      onHorizontalDragEnd: (_) {
        final shouldReply = _offset >= _threshold;
        _reset();
        if (shouldReply) widget.onReply();
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          if (_offset > 0)
            Positioned(
              left: widget.incoming ? null : 8,
              right: widget.incoming ? -(28 + slide) : null,
              child: Opacity(
                opacity: (_offset / _threshold).clamp(0.0, 1.0),
                child: Icon(
                  Icons.reply_rounded,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          TweenAnimationBuilder<double>(
            tween: Tween(end: slide),
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: widget.child,
            builder: (context, offset, child) =>
                Transform.translate(offset: Offset(offset, 0), child: child),
          ),
        ],
      ),
    );
  }
}
