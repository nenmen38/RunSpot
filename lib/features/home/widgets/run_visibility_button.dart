import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/privacy_controls.dart';
import '../live_map_controller.dart';

class RunVisibilityButton extends StatefulWidget {
  const RunVisibilityButton({
    required this.controller,
    required this.client,
    required this.active,
    super.key,
  });

  final LiveMapController controller;
  final SupabaseClient client;
  final bool active;

  @override
  State<RunVisibilityButton> createState() => _RunVisibilityButtonState();
}

class _RunVisibilityButtonState extends State<RunVisibilityButton> {
  late Future<String?> _visibility = _loadVisibility();

  @override
  void didUpdateWidget(covariant RunVisibilityButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.active && widget.active) ||
        oldWidget.controller != widget.controller) {
      _visibility = _loadVisibility();
    }
  }

  Future<String?> _loadVisibility() async {
    final session = widget.client.auth.currentSession;
    if (session == null) return null;
    final profile = await widget.client
        .from('profiles')
        .select('visibility,nickname')
        .eq('id', session.user.id)
        .setHeader('Authorization', 'Bearer ${session.accessToken}')
        .maybeSingle();
    if (widget.client.auth.currentSession?.user.id != session.user.id ||
        session.user.emailConfirmedAt == null ||
        profile?['nickname'] == null) {
      return null;
    }
    return profile?['visibility'] as String?;
  }

  Future<void> _open() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .8,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            PrivacyControls(
              sharingController: widget.controller,
              showIdentity: false,
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() => _visibility = _loadVisibility());
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return FutureBuilder(
      future: _visibility,
      builder: (context, snapshot) {
        final audience = switch (snapshot.data) {
          'friends' => '친구에게만',
          'public' => '전체에',
          'private' => '비공개',
          _ => null,
        };
        final label = controller.sharing
            ? audience == '친구에게만' || audience == '전체에'
                  ? '위치 $audience 공유 중'
                  : '위치 공유 중'
            : !controller.shareWhileRunning || audience == '비공개'
            ? '위치 공유 꺼짐'
            : controller.runSession != null
            ? '위치 공유 중지됨'
            : audience == null
            ? '러닝 시작 전 위치 공개 범위 확인'
            : '출발하면 위치를 $audience 공유';
        return TextButton.icon(
          onPressed: _open,
          icon: Icon(
            controller.sharing ? Icons.location_on : Icons.lock_outline,
          ),
          label: Text(label),
        );
      },
    );
  }
}
