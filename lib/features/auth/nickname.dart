import 'data/nickname_service.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({required this.service, super.key});
  final NicknameService service;

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _controller = TextEditingController();
  NicknameState? _state;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _state = null;
    });
    try {
      final state = await widget.service.load();
      if (!mounted) return;
      _controller.text = state.nickname ?? '';
      setState(() => _state = state);
    } catch (_) {
      if (mounted) setState(() => _error = '닉네임 정보를 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _state?.canChange(DateTime.now()) != true) return;
    final error = validateNickname(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.save(_controller.text);
      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = switch (error.code) {
            '23505' => '이미 사용 중인 닉네임입니다.',
            '42501' => '이메일 인증 상태를 확인해 주세요.',
            'P0001' => '닉네임은 30일에 한 번 변경할 수 있습니다.',
            '22023' => '닉네임 형식을 확인해 주세요.',
            _ => '닉네임을 저장하지 못했습니다. 다시 시도해 주세요.',
          },
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '닉네임을 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canChange = _state?.canChange(DateTime.now()) == true;
    final next = _state?.nextChangeAt?.toLocal();
    return Scaffold(
      appBar: AppBar(title: const Text('닉네임')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_state != null && !_state!.verified)
                const Text('이메일 인증 후 닉네임을 등록할 수 있습니다.'),
              if (_state?.verified == true && !canChange && next != null)
                Text(
                  '변경 가능: ${next.year}년 ${next.month}월 ${next.day}일 ${next.hour}시 ${next.minute}분',
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_busy && canChange,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '닉네임',
                  helperText: '한글·영문·숫자·밑줄 2~30자',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_state == null && !_busy)
                TextButton(onPressed: _load, child: const Text('다시 시도')),
              FilledButton(
                onPressed: !_busy && canChange ? _save : null,
                child: const Text('저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
