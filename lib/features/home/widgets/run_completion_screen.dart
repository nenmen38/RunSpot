import 'package:flutter/material.dart';

import '../../../shared/layout/readable_width.dart';
import '../../../shared/widgets/panel.dart';
import '../../run_history/models/run_record.dart';
import '../../run_history/widgets/run_record_details.dart';
import '../../run_share/models/share_route.dart';

enum RunCompletionAction { share, history, hide }

class RunCompletionScreen extends StatelessWidget {
  const RunCompletionScreen({
    required this.record,
    required this.route,
    required this.isCurrentOwner,
    this.ownerChanges,
    this.details = const [],
    super.key,
  });

  final RunRecord record;
  final ShareRoute route;
  final bool Function() isCurrentOwner;
  final Stream<Object?>? ownerChanges;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: ownerChanges,
    builder: (context, _) {
      final canRead = isCurrentOwner();
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            canRead
                ? record.pendingSync
                      ? '기기에 저장됨'
                      : '러닝 완료'
                : '러닝 결과',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        ),
        body: !canRead
            ? const Center(child: Text('로그인 상태를 확인해 주세요.'))
            : ReadableWidth(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    _RunSummaryHero(record: record, route: route),
                    const SizedBox(height: 12),
                    Panel(
                      child: RunRecordDetails(
                        record: record,
                        showDistance: false,
                      ),
                    ),
                    for (final detail in details)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: detail,
                      ),
                    if (record.distanceMeters == 0 && !record.pendingSync)
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, RunCompletionAction.hide),
                        child: const Text('기록 숨기기'),
                      ),
                  ],
                ),
              ),
        bottomNavigationBar: canRead
            ? SafeArea(
                top: false,
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: () => Navigator.pop(
                              context,
                              RunCompletionAction.share,
                            ),
                            icon: const Icon(Icons.ios_share),
                            label: const Text('공유 카드 만들기'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(
                              context,
                              RunCompletionAction.history,
                            ),
                            child: const Text('내 기록'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : null,
      );
    },
  );
}

class _RunSummaryHero extends StatelessWidget {
  const _RunSummaryHero({required this.record, required this.route});
  final RunRecord record;
  final ShareRoute route;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF163454), Color(0xFF101D2B)],
      ),
    ),
    child: Column(
      children: [
        Text(
          '${(record.distanceMeters / 1000).toStringAsFixed(2)} km',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        if (!route.isEmpty) ...[
          const SizedBox(height: 16),
          Semantics(
            container: true,
            image: true,
            label: '이번 러닝 경로',
            child: SizedBox(
              width: double.infinity,
              height: 150,
              child: CustomPaint(painter: _RunRoutePainter(route)),
            ),
          ),
        ],
      ],
    ),
  );
}

class _RunRoutePainter extends CustomPainter {
  const _RunRoutePainter(this.route);

  final ShareRoute route;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide - 16;
    if (side <= 0) return;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    final path = Path();
    for (final segment in route.segments) {
      path.addPolygon([
        for (final point in segment) origin + point * side,
      ], false);
    }
    final paint = Paint()
      ..color = const Color(0xFF8EEBD8)
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RunRoutePainter oldDelegate) =>
      oldDelegate.route != route;
}
