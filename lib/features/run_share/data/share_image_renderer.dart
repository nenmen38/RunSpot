import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../shared/formatters/run_format.dart';
import '../../run_history/models/run_record.dart';
import '../../run_history/widgets/run_record_details.dart';
import '../models/share_route.dart';

class ShareImageRenderer {
  Future<Uint8List> render(
    RunRecord record, {
    ShareRoute? route,
    ui.Image? background,
    bool dark = false,
    double height = 1920,
    Color? textColor,
    bool photoOverlay = false,
  }) async {
    if (!height.isFinite || height < 1512 || height > 3240) {
      throw const FormatException('공유 이미지 크기가 올바르지 않습니다.');
    }
    const width = 1080.0;
    const inset = 72.0;
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
    final solidBackground = onDark
        ? const Color(0xFF22282C)
        : const Color(0xFFF8FAFC);
    final comparisonBackground = photo == null
        ? solidBackground
        : Color.alphaBlend(scrim, lightInk ? Colors.white : Colors.black);
    final inkLuminance = foreground.computeLuminance();
    final backdropLuminance = comparisonBackground.computeLuminance();
    final contrast = inkLuminance > backdropLuminance
        ? (inkLuminance + .05) / (backdropLuminance + .05)
        : (backdropLuminance + .05) / (inkLuminance + .05);
    final needsOutline = photo != null || contrast < 4.5;
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
      TextPainter painter(double fontSize, {bool outline = false}) =>
          TextPainter(
            text: TextSpan(
              text: value,
              style: TextStyle(
                color: outline ? null : color ?? foreground,
                foreground: outline
                    ? (Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3
                        ..color = lightInk
                            ? const Color(0xFF171A1D)
                            : Colors.white)
                    : null,
                fontSize: fontSize,
                fontWeight: weight,
                height: 1.25,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: photo == null || outline
                    ? null
                    : [
                        Shadow(
                          color: lightInk
                              ? const Color(0x99000000)
                              : const Color(0x99FFFFFF),
                          blurRadius: 3,
                          offset: const Offset(0, 2),
                        ),
                      ],
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
      if (needsOutline) {
        final outline = painter(fontSize, outline: true);
        outline.paint(canvas, position);
        outline.dispose();
      }
      text.paint(canvas, position);
      text.dispose();
    }

    const metricsHeight = 405.0;
    const routeSide = 520.0;
    const routeGap = 80.0;
    final hasRoute = route != null && !route.isEmpty;
    final groupHeight = metricsHeight + (hasRoute ? routeSide + routeGap : 0);
    final groupTop = (height - groupHeight) / 2;
    final metricsTop = groupTop + (hasRoute ? routeSide + routeGap : 0);
    if (hasRoute) {
      const side = routeSide;
      final left = (width - side) / 2;
      final top = groupTop;
      final paint = Paint()
        ..color = (photo != null ? lightInk : onDark)
            ? const Color(0xFF7AE6C5)
            : const Color(0xFF16836F)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final segment in route.segments) {
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

    label(
      '거리',
      30,
      Offset(inset, metricsTop),
      color: secondary,
      centered: true,
    );
    label(
      (record.distanceMeters / 1000).toStringAsFixed(2),
      168,
      Offset(inset, metricsTop + 35),
      weight: FontWeight.w900,
      centered: true,
    );
    label(
      'km',
      32,
      Offset(inset, metricsTop + 225),
      color: secondary,
      centered: true,
    );
    const gap = 24.0;
    const columnWidth = (contentWidth - gap * 2) / 3;
    final values = [
      ('시간', formatRunDuration(Duration(seconds: record.durationSeconds))),
      ('평균 페이스', formatRunPace(record)),
      ('기온', record.temperature?.label ?? '--'),
    ];
    for (var i = 0; i < values.length; i++) {
      final x = inset + i * (columnWidth + gap);
      label(
        values[i].$2,
        50,
        Offset(x, metricsTop + 295),
        weight: FontWeight.w700,
        maxWidth: columnWidth,
        centered: true,
      );
      label(
        values[i].$1,
        28,
        Offset(x, metricsTop + 365),
        color: secondary,
        maxWidth: columnWidth,
        centered: true,
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
