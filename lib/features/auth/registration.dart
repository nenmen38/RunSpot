import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String? validateRegistration(
  bool accepted,
  String? termsId, {
  bool testMode = false,
}) {
  if (testMode && kDebugMode) return null;
  if (termsId == null) return '현재 가입 약관이 준비되지 않았습니다.';
  if (!accepted) return '이용약관에 동의해 주세요.';
  return null;
}

class RegistrationFields extends StatefulWidget {
  const RegistrationFields({
    required this.onChanged,
    this.loadTerms,
    this.loadTestMode,
    this.onTestModeChanged,
    super.key,
  });
  final void Function(String? termsId, bool accepted) onChanged;
  final Future<Map<String, dynamic>?> Function()? loadTerms;
  final Future<bool> Function()? loadTestMode;
  final ValueChanged<bool>? onTestModeChanged;

  @override
  State<RegistrationFields> createState() => _RegistrationFieldsState();
}

class _RegistrationFieldsState extends State<RegistrationFields> {
  Map<String, dynamic>? _terms;
  bool _accepted = false;
  bool _loading = true;
  String? _error;
  bool _testMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _accepted = false;
      _testMode = false;
    });
    widget.onChanged(null, false);
    widget.onTestModeChanged?.call(false);
    try {
      final testMode =
          kDebugMode &&
          (widget.loadTestMode != null
              ? await widget.loadTestMode!()
              : widget.loadTerms == null &&
                    await Supabase.instance.client.rpc(
                          'registration_test_mode',
                        ) ==
                        true);
      if (!mounted) return;
      if (testMode) {
        setState(() {
          _testMode = true;
          _loading = false;
        });
        widget.onTestModeChanged?.call(true);
        return;
      }
      final terms = widget.loadTerms != null
          ? await widget.loadTerms!()
          : await Supabase.instance.client
                .from('registration_terms')
                .select('id,version,title,body')
                .eq('is_current', true)
                .maybeSingle();
      if (!mounted) return;
      setState(() {
        _terms = terms;
        _loading = false;
      });
      widget.onChanged(terms?['id'] as String?, false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '약관을 불러오지 못했습니다.';
      });
    }
  }

  void _showTerms() {
    final terms = _terms!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${terms['title']} (${terms['version']})'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(terms['body'] as String),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 10),
      if (_testMode)
        const Text('테스트 가입 · 약관 동의 생략')
      else if (_loading)
        const LinearProgressIndicator()
      else if (_error != null)
        Row(
          children: [
            Expanded(child: Text(_error!)),
            IconButton(
              onPressed: _load,
              tooltip: '약관 다시 불러오기',
              icon: const Icon(Icons.refresh),
            ),
          ],
        )
      else if (_terms == null)
        const Text('현재 가입 약관이 준비되지 않았습니다.')
      else ...[
        TextButton(onPressed: _showTerms, child: const Text('이용약관 전문 보기')),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('[필수] 이용약관 동의'),
          controlAffinity: ListTileControlAffinity.leading,
          value: _accepted,
          onChanged: (value) {
            setState(() => _accepted = value ?? false);
            widget.onChanged(_terms!['id'] as String, _accepted);
          },
        ),
      ],
    ],
  );
}

class RegistrationGate extends StatefulWidget {
  const RegistrationGate({required this.child, super.key});
  final Widget child;
  @override
  State<RegistrationGate> createState() => _RegistrationGateState();
}

class _RegistrationGateState extends State<RegistrationGate> {
  bool? _complete;
  bool _busy = false;
  bool _accepted = false;
  String? _termsId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _error = null);
    try {
      var complete = await Supabase.instance.client.rpc(
        'my_registration_complete',
      ) as bool;
      if (!complete &&
          kDebugMode &&
          await Supabase.instance.client.rpc('registration_test_mode') ==
              true) {
        await Supabase.instance.client.rpc('complete_test_registration');
        complete =
            await Supabase.instance.client.rpc('my_registration_complete') ==
            true;
      }
      if (mounted) setState(() => _complete = complete);
    } catch (_) {
      if (mounted) setState(() => _error = '가입 상태를 확인하지 못했습니다.');
    }
  }

  Future<void> _save() async {
    final error = validateRegistration(_accepted, _termsId);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'complete_registration',
        params: {'accepted_terms': _termsId},
      );
      if (mounted) setState(() => _complete = true);
    } on PostgrestException {
      if (mounted) {
        setState(() => _error = '가입을 완료하지 못했습니다. 현재 약관을 확인해 주세요.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '가입 처리 중 오류가 발생했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_complete == true) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('가입 완료', style: Theme.of(context).textTheme.titleLarge),
              if (_complete == null && _error == null)
                const LinearProgressIndicator(),
              if (_complete == false) ...[
                RegistrationFields(
                  onChanged: (id, accepted) {
                    _termsId = id;
                    _accepted = accepted;
                  },
                ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? '처리 중' : '가입 완료'),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_complete == null && _error != null)
                TextButton(onPressed: _check, child: const Text('다시 시도')),
              TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        try {
                          await Supabase.instance.client.auth.signOut();
                        } catch (_) {
                          if (mounted) setState(() => _error = '로그아웃하지 못했습니다.');
                        }
                      },
                child: const Text('로그아웃'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
