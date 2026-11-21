import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/formatters/run_format.dart';
import '../board/data/board_photo_service.dart';
import '../run_history/data/run_record_service.dart';
import '../run_history/models/run_record.dart';
import '../run_history/widgets/run_record_details.dart';

class FriendChatDraft {
  const FriendChatDraft({
    required this.id,
    this.body,
    this.replyTo,
    this.photo,
    this.runId,
  });

  final String id;
  final String? body;
  final int? replyTo;
  final String? photo;
  final String? runId;
}

class FriendChatPhotoException implements Exception {
  const FriendChatPhotoException(this.message);

  final String message;
}

Future<Uint8List?> pickFriendChatPhoto(BuildContext context) async {
  Uint8List bytes;
  try {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    if (await file.length() > 20 * 1024 * 1024) {
      throw const BoardPhotoException('20MB 이하의 사진을 선택해 주세요.');
    }
    bytes = await encodeBoardPhoto(await file.readAsBytes());
  } on BoardPhotoException catch (error) {
    throw FriendChatPhotoException(error.message);
  } catch (_) {
    throw const FriendChatPhotoException('사진을 불러올 수 없습니다. 사진 접근 권한을 확인해 주세요.');
  }
  if (bytes.length > 1024 * 1024) {
    bytes = await compute(_compressChatPhoto, bytes);
  }
  if (!context.mounted) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('사진 보내기'),
      content: Image.memory(bytes, fit: BoxFit.contain),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('보내기'),
        ),
      ],
    ),
  );
  return confirmed == true ? bytes : null;
}

// 메타데이터가 제거된 사진을 줄여 서버의 전송 한도에 맞춥니다.
Uint8List _compressChatPhoto(Uint8List bytes) {
  var image = img.decodeJpg(bytes);
  if (image == null) throw const FriendChatPhotoException('사진을 읽을 수 없습니다.');
  var result = bytes;
  while (result.length > 1024 * 1024 &&
      image!.width > 160 &&
      image.height > 160) {
    image = img.copyResize(image, width: (image.width * .8).round());
    result = img.encodeJpg(image, quality: 78);
  }
  if (result.length > 1024 * 1024) {
    throw const FriendChatPhotoException('사진을 압축하지 못했습니다. 다른 사진을 선택해 주세요.');
  }
  return result;
}

class FriendChatPhoto extends StatefulWidget {
  const FriendChatPhoto({required this.load, super.key});

  final Future<Uint8List> Function() load;

  @override
  State<FriendChatPhoto> createState() => _FriendChatPhotoState();
}

class _FriendChatPhotoState extends State<FriendChatPhoto> {
  late Future<Uint8List> _photo = widget.load();

  Future<void> _enlarge(Uint8List bytes) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(bytes)),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                color: Colors.white,
                tooltip: '닫기',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _photo,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(() => _photo = widget.load()),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          child: const Text('사진 다시 불러오기'),
        );
      }
      if (snapshot.data case final bytes?) {
        return GestureDetector(
          onTap: () => _enlarge(bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              bytes,
              width: 210,
              height: 150,
              fit: BoxFit.cover,
              cacheWidth: 420,
              semanticLabel: '사진 확대',
              errorBuilder: (_, _, _) => const Text('사진을 표시할 수 없습니다.'),
            ),
          ),
        );
      }
      return const SizedBox(
        width: 210,
        height: 150,
        child: Center(child: CircularProgressIndicator()),
      );
    },
  );
}

String _runMetrics(int distance, int seconds) {
  final metrics =
      '${(distance / 1000).toStringAsFixed(2)} km · '
      '${formatRunDuration(Duration(seconds: seconds))}';
  if (distance <= 0 || seconds <= 0) return '$metrics · 평균 페이스 —';

  final pace = (seconds * 1000 / distance).round();
  return '$metrics · ${formatPaceDuration(Duration(seconds: pace))} /km';
}

class FriendChatRunCard extends StatelessWidget {
  const FriendChatRunCard({
    required this.summary,
    required this.mine,
    super.key,
  });

  final Map<dynamic, dynamic> summary;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final color = mine ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_run_rounded, color: color, size: 20),
            const SizedBox(width: 4),
            Text(
              '달리기 기록',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _runMetrics(
            summary['distance_m'] as int,
            summary['duration_sec'] as int,
          ),
          style: TextStyle(color: color),
        ),
      ],
    );
  }
}

Future<String?> pickFriendChatRun(BuildContext context, SupabaseClient client) {
  final service = SupabaseRunRecordService(client);
  return showModalBottomSheet<String>(
    isScrollControlled: true,
    context: context,
    builder: (context) => _RunPicker(service: service),
  );
}

class _RunPicker extends StatefulWidget {
  const _RunPicker({required this.service});

  final RunRecordService service;

  @override
  State<_RunPicker> createState() => _RunPickerState();
}

class _RunPickerState extends State<_RunPicker> {
  final _records = <RunRecord>[];
  int _offset = 0;
  bool _more = true;
  bool _loading = false;
  bool _failed = false;
  RunRecord? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    const limit = 30;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.service.list(offset: _offset, limit: limit);
      if (!mounted) return;
      setState(() {
        _records.addAll(page.where((record) => !record.hidden));
        _offset += page.length;
        _more = page.length == limit;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .68,
      child: Column(
        children: [
          ListTile(
            title: const Text('기록 자랑하기'),
            subtitle: const Text('거리, 시간, 평균 페이스를 공유합니다.'),
            trailing: TextButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(context, _selected!.id),
              child: const Text('보내기'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _records.length + 1,
              itemBuilder: (context, index) {
                if (index == _records.length) {
                  if (_loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_more) {
                    return TextButton(
                      onPressed: _load,
                      child: Text(_failed ? '다시 불러오기' : '이전 기록 더 보기'),
                    );
                  }
                  return _records.isEmpty
                      ? const Center(child: Text('공유할 기록이 없습니다.'))
                      : const SizedBox.shrink();
                }
                final record = _records[index];
                return ListTile(
                  selected: _selected?.id == record.id,
                  leading: Icon(
                    _selected?.id == record.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(formatRunDate(record.startedAt)),
                  subtitle: Text(
                    _runMetrics(record.distanceMeters, record.durationSeconds),
                  ),
                  onTap: () => setState(() => _selected = record),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
