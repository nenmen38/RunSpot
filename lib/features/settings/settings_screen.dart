import 'package:flutter/material.dart';

import '../health/data/run_health_service.dart';
import '../health/health_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.adminBuilder,
    required this.isCurrentOwner,
    this.onBlockedUsersTap,
    super.key,
  });

  final WidgetBuilder adminBuilder;
  final VoidCallback? onBlockedUsersTap;
  final bool Function() isCurrentOwner;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: ListView(
      children: [
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
        ListTile(
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
        ),
      ],
    ),
  );
}
