import 'widgets/board_theme.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:uuid/uuid.dart';

import 'board_controller.dart';
import 'data/board_photo_service.dart';
import 'models/board_post.dart';
import 'widgets/board_photo.dart';
import 'widgets/board_post_tile.dart';

const _maxPhotos = 4;

/// 새로 고른 사진은 [bytes]를, 이미 올린 사진은 [path]를 가집니다.
class _Photo {
  _Photo({this.bytes, this.path, this.url});
  final Uint8List? bytes;
  String? path;
  final String? url;
}

class BoardComposeScreen extends StatefulWidget {
  const BoardComposeScreen({
    required this.controller,
    this.photoService,
    this.post,
    super.key,
  });

  final BoardController controller;

  /// 없으면 기기 갤러리에서 사진을 고릅니다.
  final BoardPhotoService? photoService;

  /// 수정할 글입니다. 없으면 현재 게시판에 새 글을 씁니다.
  final BoardPost? post;

  @override
  State<BoardComposeScreen> createState() => _BoardComposeScreenState();
}

class _BoardComposeScreenState extends State<BoardComposeScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.post?.title);
  late final _body = TextEditingController(text: widget.post?.body);
  late final _place = TextEditingController(text: widget.post?.racePlace);
  late final _url = TextEditingController(text: widget.post?.raceUrl);
  // 같은 화면에서 다시 등록하면 서버가 같은 글로 처리합니다.
  final _clientId = const Uuid().v4();
  late final BoardKind _kind = widget.post?.kind ?? widget.controller.kind;
  late BoardTopic? _topic = widget.post?.topic ?? widget.controller.topic;
  late DateTime? _raceDate = widget.post?.raceDate;
  late final List<_Photo> _photos = [
    for (final path in widget.post?.images ?? const <String>[])
      _Photo(path: path, url: widget.post!.imageUrls[path]),
  ];
  // 이 화면에서 새로 올린 사진입니다. 저장하지 않고 나가면 지웁니다.
  final _uploaded = <String>{};
  bool _saved = false;
  bool _picking = false;
  bool _uploading = false;
  bool _submitted = false;
  String? _error;

  bool get _isRace => _kind == BoardKind.race;
  bool get _isEditing => widget.post != null;
  bool get _busy => _picking || _uploading || widget.controller.busy;

  @override
  void dispose() {
    if (!_saved) unawaited(widget.controller.removePhotos(_uploaded.toList()));
    _title.dispose();
    _body.dispose();
    _place.dispose();
    _url.dispose();
    super.dispose();
  }

  String? _required(String? value, String emptyMessage, int max) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return emptyMessage;
    if (text.length > max) return '$max자 이내로 입력해 주세요.';
    return null;
  }

  String? _validateUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'https://로 시작하는 주소를 입력해 주세요.';
    }
    return text.length > 500 ? '주소가 너무 깁니다.' : null;
  }

  Future<void> _pickPhotos() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await (widget.photoService ?? GalleryBoardPhotoService())
          .pick(_maxPhotos - _photos.length);
      if (mounted) {
        setState(
          () => _photos.addAll(picked.map((bytes) => _Photo(bytes: bytes))),
        );
      }
    } on BoardPhotoException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // 이미 지난 날짜의 공지를 고칠 때도 기존 날짜를 그대로 보여줍니다.
    final picked = await showDatePicker(
      context: context,
      builder: (_, child) => BoardTheme(child: child!),
      firstDate: _raceDate != null && _raceDate!.isBefore(today)
          ? _raceDate!
          : today,
      lastDate: today.add(const Duration(days: 730)),
      initialDate: _raceDate ?? today,
    );
    if (picked != null && mounted) setState(() => _raceDate = picked);
  }

  /// 새 사진만 올리고 경로를 기억해 다시 시도할 때 중복으로 올리지 않습니다.
  Future<bool> _uploadPhotos() async {
    setState(() => _uploading = true);
    try {
      for (final photo in _photos) {
        if (photo.path != null) continue;
        photo.path = await widget.controller.uploadPhoto(photo.bytes!);
        _uploaded.add(photo.path!);
      }
      return true;
    } catch (exception) {
      if (mounted) {
        setState(() => _error = widget.controller.photoError(exception));
      }
      return false;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    final valid = _form.currentState!.validate();
    if (!valid || (_isRace ? _raceDate == null : _topic == null)) return;
    if (!await _uploadPhotos() || !mounted) return;
    final draft = BoardDraft(
      clientId: _clientId,
      kind: _kind,
      topic: _isRace ? null : _topic,
      title: _title.text.trim(),
      body: _body.text.trim(),
      raceDate: _isRace ? _raceDate : null,
      racePlace: _isRace ? _place.text.trim() : null,
      raceUrl: _isRace && _url.text.trim().isNotEmpty ? _url.text.trim() : null,
      images: [for (final photo in _photos) photo.path!],
    );
    final editing = widget.post;
    final error = editing == null
        ? await widget.controller.create(draft)
        : await widget.controller.update(editing, draft);
    if (!mounted) return;
    if (error == null) {
      _saved = true;
      if (editing != null) {
        // 글에서 뺀 기존 사진은 저장이 끝난 뒤에 지웁니다.
        unawaited(
          widget.controller.removePhotos(
            editing.images
                .where((path) => !draft.images.contains(path))
                .toList(),
          ),
        );
      }
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final region = widget.post?.region ?? widget.controller.region;
    return BoardTheme(
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(
              _isEditing
                  ? '글 수정'
                  : _isRace
                  ? '러닝 대회 공지 등록'
                  : '${_kind.label} 게시판 글쓰기',
            ),
          ),
          body: Form(
            key: _form,
            // 화면 밖 입력칸도 검사되도록 모든 칸을 한 번에 만듭니다.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_kind == BoardKind.local && region != null) ...[
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: BoardStyle.accent,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '$region 게시판${_isEditing ? '의 글이에요' : '에 등록돼요'}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!_isRace) ...[
                    Text('말머리', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final topic in BoardTopic.values)
                          ChoiceChip(
                            label: Text(topic.label),
                            selected: _topic == topic,
                            onSelected: (_) => setState(() => _topic = topic),
                          ),
                      ],
                    ),
                    if (_submitted && _topic == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '말머리를 선택해 주세요.',
                          style: TextStyle(
                            color: BoardStyle.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    // 조건부 안내 문구가 끼어들어도 입력 상태가 다른 칸으로 옮겨지지 않게 합니다.
                    key: const ValueKey('title'),
                    controller: _title,
                    maxLength: 80,
                    decoration: InputDecoration(
                      labelText: _isRace ? '대회 이름' : '제목',
                    ),
                    validator: (value) => _required(
                      value,
                      _isRace ? '대회 이름을 입력해 주세요.' : '제목을 입력해 주세요.',
                      80,
                    ),
                  ),
                  if (_isRace) ...[
                    ListTile(
                      key: const ValueKey('race-date'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(
                        _raceDate == null
                            ? '대회 날짜 선택'
                            : formatRaceDate(_raceDate!),
                      ),
                      subtitle: _submitted && _raceDate == null
                          ? const Text(
                              '대회 날짜를 선택해 주세요.',
                              style: TextStyle(color: BoardStyle.error),
                            )
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickDate,
                    ),
                    TextFormField(
                      key: const ValueKey('place'),
                      controller: _place,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: '장소'),
                      validator: (value) =>
                          _required(value, '장소를 입력해 주세요.', 80),
                    ),
                    TextFormField(
                      key: const ValueKey('url'),
                      controller: _url,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '접수·안내 링크 (선택)',
                        hintText: 'https://',
                      ),
                      validator: _validateUrl,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    key: const ValueKey('body'),
                    controller: _body,
                    // 기기 키보드의 이모티콘을 그대로 입력할 수 있습니다.
                    keyboardType: TextInputType.multiline,
                    maxLength: 2000,
                    minLines: 6,
                    maxLines: 12,
                    decoration: InputDecoration(
                      labelText: _isRace ? '접수 기간·종목 등 안내' : '내용',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) =>
                        _required(value, '내용을 입력해 주세요.', 2000),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    key: const ValueKey('photos-header'),
                    children: [
                      Text(
                        '사진 ${_photos.length}/$_maxPhotos',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      TextButton.icon(
                        onPressed: _photos.length >= _maxPhotos || _busy
                            ? null
                            : _pickPhotos,
                        icon: _picking
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('사진 추가'),
                      ),
                    ],
                  ),
                  if (_photos.isNotEmpty)
                    Wrap(
                      key: const ValueKey('photos'),
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final photo in _photos)
                          Stack(
                            children: [
                              photo.bytes == null && photo.url == null
                                  ? Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        color: AppColors.line,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.image_outlined),
                                    )
                                  : BoardPhoto(
                                      bytes: photo.bytes,
                                      url: photo.url,
                                      size: 76,
                                    ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: IconButton(
                                  tooltip: '사진 빼기',
                                  constraints: const BoxConstraints(
                                    minWidth: 44,
                                    minHeight: 44,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _photos.remove(photo),
                                        ),
                                  icon: const CircleAvatar(
                                    radius: 11,
                                    backgroundColor: Colors.black54,
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                      semanticLabel: '사진 빼기',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      '사진의 촬영 위치 등 기기 정보는 지우고 올려요.',
                      style: TextStyle(
                        color: BoardStyle.secondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: BoardStyle.error),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _uploading || widget.controller.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEditing ? '수정 완료' : '등록'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
