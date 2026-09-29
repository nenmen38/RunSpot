import 'package:flutter/material.dart';
import 'package:runquest/features/course/models/route_plan.dart';
import 'package:runquest/shared/theme/app_colors.dart';

class RouteMapPreview extends StatelessWidget {
  const RouteMapPreview({required this.plan, super.key});

  final RoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CustomPaint(
        painter: RouteMapPainter(),
        child: Stack(
          children: [
            const Positioned(
              left: 10,
              top: 10,
              child: MapPill(icon: Icons.my_location, text: '출발 숨김'),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: MapPill(icon: Icons.flag_outlined, text: plan.distance),
            ),
          ],
        ),
      ),
    );
  }
}

class RouteMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF2F6FB),
    );

    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), road);
    }
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 8), Offset(x, size.height - 8), road);
    }

    final park = Paint()..color = AppColors.green.withValues(alpha: .14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .56,
          size.height * .12,
          size.width * .31,
          size.height * .27,
        ),
        const Radius.circular(12),
      ),
      park,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .08,
          size.height * .58,
          size.width * .35,
          size.height * .24,
        ),
        const Radius.circular(12),
      ),
      park,
    );

    final route = Path()
      ..moveTo(size.width * .22, size.height * .70)
      ..cubicTo(
        size.width * .14,
        size.height * .28,
        size.width * .44,
        size.height * .14,
        size.width * .66,
        size.height * .25,
      )
      ..cubicTo(
        size.width * .88,
        size.height * .35,
        size.width * .82,
        size.height * .72,
        size.width * .57,
        size.height * .78,
      )
      ..cubicTo(
        size.width * .42,
        size.height * .82,
        size.width * .30,
        size.height * .80,
        size.width * .22,
        size.height * .70,
      );

    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.blueSoft
        ..strokeWidth = 15
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.blue
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final start = Offset(size.width * .22, size.height * .70);
    canvas.drawCircle(start, 8, Paint()..color = AppColors.ink);
    canvas.drawCircle(start, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MapPill extends StatelessWidget {
  const MapPill({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.blue),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
