import 'package:flutter/material.dart';

import '../../moderation/report_dialog.dart';
import 'board_theme.dart';

class BoardReportDialog extends StatelessWidget {
  const BoardReportDialog({this.isComment = false, super.key});
  final bool isComment;

  @override
  Widget build(BuildContext context) => BoardTheme(
    child: ReportDialog(title: isComment ? '댓글 신고' : '게시글 신고'),
  );
}
