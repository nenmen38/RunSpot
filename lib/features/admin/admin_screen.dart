import 'package:flutter/material.dart';
import 'package:runquest/features/admin/models/review_case.dart';
import 'package:runquest/features/admin/widgets/review_widgets.dart';
import 'package:runquest/shared/widgets/page_layout.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({required this.review, required this.onAction, super.key});

  final ReviewCase review;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(title: '관리', subtitle: '기록 신뢰도를 지키는 운영 화면'),
          const SizedBox(height: 12),
          const AdminStats(),
          const SizedBox(height: 10),
          Expanded(
            child: AdminReviewCard(review: review, onAction: onAction),
          ),
        ],
      ),
    );
  }
}
