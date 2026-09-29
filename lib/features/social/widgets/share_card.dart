import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:runquest/shared/widgets/panel.dart';

class ShareCard extends StatelessWidget {
  const ShareCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.all(12),
      child: const Row(
        children: [
          Icon(Icons.ios_share, color: AppColors.blue),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '인스타/페이스북 공유 카드 생성 · 위치는 자동 보호',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
