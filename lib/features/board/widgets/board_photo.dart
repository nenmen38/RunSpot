import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';

/// 게시판 사진을 둥근 모서리로 표시하고 불러오기 실패 시 빈 칸을 보여줍니다.
class BoardPhoto extends StatelessWidget {
  const BoardPhoto({
    this.url,
    this.bytes,
    this.size,
    this.aspectRatio,
    super.key,
  }) : assert(url != null || bytes != null);

  final String? url;
  final Uint8List? bytes;
  final double? size;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    Widget placeholder(IconData icon) => ColoredBox(
      color: AppColors.line,
      child: Center(child: Icon(icon, color: AppColors.gray)),
    );
    final image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true)
        : Image.network(
            url!,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder(Icons.image_outlined),
            errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
          );
    final clipped = ClipRRect(
      borderRadius: BorderRadius.circular(size == null ? 14 : 10),
      child: image,
    );
    if (size != null) return SizedBox.square(dimension: size, child: clipped);
    return AspectRatio(aspectRatio: aspectRatio ?? 4 / 3, child: clipped);
  }
}
