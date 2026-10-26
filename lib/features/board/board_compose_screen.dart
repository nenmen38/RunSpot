import 'package:flutter/material.dart';
import 'package:runquest/shared/theme/app_colors.dart';
import 'package:uuid/uuid.dart';

import 'board_controller.dart';
import 'models/board_post.dart';
import 'widgets/board_post_tile.dart';

class BoardComposeScreen extends StatefulWidget {
  const BoardComposeScreen({required this.controller, super.key});

  final BoardController controller;

  @override
  State<BoardComposeScreen> createState() => _BoardComposeScreenState();
}

class _BoardComposeScreenState extends State<BoardComposeScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _place = TextEditingController();
  final _url = TextEditingController();
  // 같은 화면에서 다시 등록하면 서버가 같은 글로 처리합니다.
  final _clientId = const Uuid().v4();
  late final BoardKind _kind = widget.controller.kind;
  late BoardTopic? _topic = widget.controller.topic;
  DateTime? _raceDate;
  bool _submitted = false;
  String? _error;

  bool get _isRace => _kind == BoardKind.race;

  @override
  void dispose() {
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      initialDate: _raceDate ?? today,
    );
    if (picked != null && mounted) setState(() => _raceDate = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    final valid = _form.currentState!.validate();
    if (!valid || (_isRace ? _raceDate == null : _topic == null)) return;
    final error = await widget.controller.create(
      BoardDraft(
        clientId: _clientId,
        kind: _kind,
        topic: _isRace ? null : _topic,
        title: _title.text.trim(),
        body: _body.text.trim(),
        raceDate: _isRace ? _raceDate : null,
        racePlace: _isRace ? _place.text.trim() : null,
        raceUrl: _isRace && _url.text.trim().isNotEmpty
            ? _url.text.trim()
            : null,
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final region = widget.controller.region;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(_isRace ? '러닝 대회 공지 등록' : '${_kind.label} 게시판 글쓰기'),
        ),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
            children: [
              if (_kind == BoardKind.local && region != null) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '$region 게시판에 등록돼요',
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
                      style: TextStyle(color: AppColors.red, fontSize: 12),
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
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    _raceDate == null ? '대회 날짜 선택' : formatRaceDate(_raceDate!),
                  ),
                  subtitle: _submitted && _raceDate == null
                      ? const Text(
                          '대회 날짜를 선택해 주세요.',
                          style: TextStyle(color: AppColors.red),
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
                  validator: (value) => _required(value, '장소를 입력해 주세요.', 80),
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
                maxLength: 2000,
                minLines: 6,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: _isRace ? '접수 기간·종목 등 안내' : '내용',
                  alignLabelWithHint: true,
                ),
                validator: (value) => _required(value, '내용을 입력해 주세요.', 2000),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.red),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: widget.controller.busy ? null : _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: widget.controller.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('등록'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
