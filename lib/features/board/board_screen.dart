import 'package:flutter/material.dart';

class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('게시판', style: Theme.of(context).textTheme.titleLarge),
      const Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48),
              SizedBox(height: 16),
              Text('게시판을 준비하고 있습니다.'),
            ],
          ),
        ),
      ),
    ],
  );
}
