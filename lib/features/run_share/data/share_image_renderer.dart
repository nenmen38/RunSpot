import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../../run_history/models/run_record.dart';
import '../../run_history/widgets/run_record_details.dart';
import '../models/share_route.dart';
import '../models/share_layout.dart';

class ShareImageRenderer {
  Future<Uint8List> render(
    RunRecord record, {
    ShareRoute? route,
    ui.Image? background,
    bool dark = false,
    double height = 1920,
    Color? textColor,
    bool photoOverlay = false,
    ShareLayout layout = ShareLayout.centered,
  }) async {
    if (!height.isFinite || height < 1512 || height > 3240) {
      throw const FormatException('공유 이미지 크기가 올바르지 않습니다.');
    }
    const width = 1080.0;
    const inset = 48.0;
    const contentWidth = width - inset * 2;
    final onDark = dark || background != null;
    final foreground =
        textColor?.withValues(alpha: 1) ??
        (onDark ? Colors.white : const Color(0xFF202428));
    final lightInk = foreground.computeLuminance() > .179;
    final secondary = textColor != null
        ? foreground
        : background != null
        ? Colors.white
        : onDark
        ? const Color(0xFFE4E9ED)
        : const Color(0xFF646C73);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final photo = background?.clone();
    final scrim = lightInk ? const Color(0x8C000000) : const Color(0x8CFFFFFF);
    canvas.drawColor(
      onDark ? const Color(0xFF22282C) : const Color(0xFFF8FAFC),
      BlendMode.src,
    );
    if (photo != null) {
      final fitted = applyBoxFit(
        BoxFit.cover,
        Size(photo.width.toDouble(), photo.height.toDouble()),
        Size(width, height),
      );
      canvas.drawImageRect(
        photo,
        Alignment.center.inscribe(
          fitted.source,
          Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
        ),
        Rect.fromLTWH(0, 0, width, height),
        Paint()..filterQuality = FilterQuality.medium,
      );
      if (photoOverlay) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, width, height),
          Paint()..color = scrim,
        );
      }
    }

    void label(
      String value,
      double size,
      Offset offset, {
      FontWeight weight = FontWeight.w500,
      Color? color,
      double maxWidth = contentWidth,
      bool centered = false,
    }) {
      TextPainter painter(double fontSize) => TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: color ?? foreground,
            fontSize: fontSize,
            fontWeight: weight,
            height: 1.25,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      var fontSize = size;
      var text = painter(size);
      if (text.width > maxWidth) {
        fontSize = size * maxWidth / text.width;
        text.dispose();
        text = painter(fontSize);
      }
      final position = centered
          ? Offset(offset.dx + (maxWidth - text.width) / 2, offset.dy)
          : offset;
      text.paint(canvas, position);
      text.dispose();
    }

    final composition = layout.compose(
      height,
      hasRoute: route != null && !route.isEmpty,
    );
    if (composition.panel case final panel?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(panel, const Radius.circular(32)),
        Paint()
          ..color = lightInk
              ? const Color(0xB322282C)
              : const Color(0xDDF8FAFC),
      );
    }
    if (composition.route case final bounds?) {
      final side = bounds.shortestSide;
      final left = bounds.center.dx - side / 2;
      final top = bounds.center.dy - side / 2;
      final paint = Paint()
        ..color = foreground
        ..strokeWidth = (side * .04).clamp(20.0, 32.0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final segment in route!.segments) {
        final path = Path();
        for (var i = 0; i < segment.length; i++) {
          final point = Offset(
            left + segment[i].dx * side,
            top + segment[i].dy * side,
          );
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
    final values = <ShareField, String>{
      ShareField.distanceLabel: '거리',
      ShareField.distance: (record.distanceMeters / 1000).toStringAsFixed(2),
      ShareField.unit: 'km',
      ShareField.durationLabel: '시간',
      ShareField.duration: formatRunDuration(
        Duration(seconds: record.durationSeconds),
      ),
      ShareField.paceLabel: '평균 페이스',
      ShareField.pace: formatRunPace(record),
      ShareField.temperatureLabel: '기온',
      ShareField.temperature: record.temperature?.label ?? '--',
    };
    for (final slot in composition.texts) {
      label(
        values[slot.field]!,
        slot.size,
        slot.rect.topLeft,
        maxWidth: slot.rect.width,
        centered: slot.centered,
        weight: slot.bold ? FontWeight.w900 : FontWeight.w500,
        color: slot.isLabel ? secondary : foreground,
      );
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width.toInt(), height.round());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('공유 이미지를 만들지 못했습니다.');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image?.dispose();
      picture.dispose();
      photo?.dispose();
    }
  }
}
