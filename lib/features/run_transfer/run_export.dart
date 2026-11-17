import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../run_history/models/run_record.dart';
import '../run_history/models/run_route.dart';
import 'run_file_codec.dart';

Future<void> exportRun(
  BuildContext context,
  RunRecord record,
  Future<RunRoute> Function() loadRoute,
  bool Function() isOwner,
) async {
  final format = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('기록 파일 내보내기'),
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('파일에 날짜·거리·시간과 전체 이동 경로가 포함됩니다. 공유할 대상을 확인해 주세요.'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'json'),
          child: const Text('런스팟 기록 파일'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'gpx'),
          child: const Text('GPX 경로 파일'),
        ),
      ],
    ),
  );
  if (format == null || !context.mounted || !isOwner()) return;
  try {
    final route = await loadRoute();
    if (!context.mounted || !isOwner()) return;
    final text = format == 'gpx'
        ? RunFileCodec.gpx(record, route)
        : RunFileCodec.encode(record, route);
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(text),
            mimeType: format == 'gpx'
                ? 'application/gpx+xml'
                : 'application/json',
          ),
        ],
        fileNameOverrides: [
          'runspot-${record.startedAt.toIso8601String().substring(0, 10)}.$format',
        ],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('기록을 내보내지 못했습니다.')));
    }
  }
}
