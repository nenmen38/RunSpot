import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.adminBuilder, super.key});

  final WidgetBuilder adminBuilder;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: ListView(
      children: [
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
