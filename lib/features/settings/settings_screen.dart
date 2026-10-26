import 'package:flutter/material.dart';

import '../health/data/run_health_service.dart';
import '../health/health_settings_screen.dart';
import '../home/live_map_controller.dart';
import '../profile/privacy_controls.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.adminBuilder,
    required this.isCurrentOwner,
    this.onBlockedUsersTap,
    this.mapController,
    this.canManage = false,
    this.managementAccess,
    super.key,
  });

  final WidgetBuilder adminBuilder;
  final LiveMapController? mapController;
  final bool canManage;
  final Future<bool>? managementAccess;
  final VoidCallback? onBlockedUsersTap;
  final bool Function() isCurrentOwner;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('계정·공개 설정'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('계정·공개 설정')),
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    PrivacyControls(
                      sharingController: mapController,
                      showIdentity: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (onBlockedUsersTap != null)
          ListTile(
            leading: const Icon(Icons.block_outlined),
            title: const Text('차단한 사용자'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onBlockedUsersTap,
          ),
        ListTile(
          leading: const Icon(Icons.favorite_border),
          title: const Text('건강 데이터 연동'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => HealthSettingsScreen(
                service: DeviceRunHealthService(),
                isCurrentOwner: isCurrentOwner,
              ),
            ),
          ),
        ),
        FutureBuilder<bool>(
          future: managementAccess,
          builder: (context, snapshot) =>
              (managementAccess == null
                  ? canManage
                  : snapshot.connectionState == ConnectionState.done &&
                        snapshot.data == true)
              ? ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('관리'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: const Text('관리')),
                        body: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                            child: adminBuilder(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('로그아웃'),
          onTap: () async {
            if (!isCurrentOwner()) return;
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('로그아웃할까요?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            );
            if (confirmed == true && context.mounted && isCurrentOwner()) {
              try {
                await Supabase.instance.client.auth.signOut();
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('로그아웃하지 못했습니다. 다시 시도해 주세요.')),
                  );
                }
              }
            }
          },
        ),
      ],
    ),
  );
}
