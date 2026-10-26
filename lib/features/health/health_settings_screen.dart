import 'package:flutter/material.dart';

import 'data/run_health_service.dart';
import 'widgets/run_health_panel.dart';

class HealthSettingsScreen extends StatefulWidget {
  const HealthSettingsScreen({
    required this.service,
    required this.isCurrentOwner,
    super.key,
  });
  final RunHealthService service;
  final bool Function() isCurrentOwner;
  @override
  State<HealthSettingsScreen> createState() => _HealthSettingsScreenState();
}

class _HealthSettingsScreenState extends State<HealthSettingsScreen> {
  bool _busy = false;
  String? _message;
  Future<void> _connect() async {
    if (_busy || !widget.isCurrentOwner()) return;
    if (!await confirmHealthAccess(context) ||
        !mounted ||
        !widget.isCurrentOwner()) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.requestAccess();
      if (mounted && widget.isCurrentOwner()) {
        setState(() => _message = '기록 상세에서 자동으로 확인합니다.');
      }
    } catch (error) {
      if (mounted && widget.isCurrentOwner()) {
        setState(
          () => _message = error is HealthAccessException
              ? error.message
              : '연동을 요청하지 못했습니다. 기기 설정을 확인하고 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('건강 데이터 연동')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Icon(Icons.favorite_outline, size: 40),
        const SizedBox(height: 20),
        const Text('심박과 활동 칼로리를 기록에 함께 확인하세요.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('아이폰'),
          subtitle: Text('건강 앱 연결'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('안드로이드'),
          subtitle: Text('헬스 커넥트 연결'),
        ),
        const SizedBox(height: 16),
        const Text('나만 보기 · 서버 저장 없음'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy || !widget.isCurrentOwner() ? null : _connect,
          child: Text(_busy ? '연결 중' : '연결하기'),
        ),
        if (_message != null) Text(_message!),
        const SizedBox(height: 12),
        const ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('연결 안내'),
          children: [
            Text(
              '갤럭시워치는 삼성 헬스와 헬스 커넥트의 동기화를 켜 주세요. 읽기 권한만 사용하며 과거 자료 조회는 기기의 허용 기간을 따릅니다. 연결 해제는 건강 앱 또는 헬스 커넥트의 앱 권한에서 할 수 있습니다.',
            ),
          ],
        ),
      ],
    ),
  );
}
