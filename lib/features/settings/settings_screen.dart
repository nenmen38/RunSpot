import '../notifications/push_settings_screen.dart';

import 'package:runquest/features/notifications/data/push_service.dart';
import 'package:flutter/material.dart';

import '../health/data/run_health_service.dart';
import '../health/health_settings_screen.dart';
import '../home/live_map_controller.dart';
import '../profile/privacy_controls.dart';

import 'package:url_launcher/url_launcher.dart';

import 'data/account_service.dart';
import 'legal_links.dart';
import 'widgets/delete_account_dialog.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.adminBuilder,
    required this.isCurrentOwner,
    this.onBlockedUsersTap,
    this.mapController,
    this.canManage = false,
    this.managementAccess,
    this.accountService,
    super.key,
  });

  final WidgetBuilder adminBuilder;
  final LiveMapController? mapController;
  final bool canManage;
  final Future<bool>? managementAccess;
  final VoidCallback? onBlockedUsersTap;
  final bool Function() isCurrentOwner;

  /// 없으면 현재 Supabase 계정으로 탈퇴를 처리합니다.
  final AccountService? accountService;

  Future<void> _open(BuildContext context, Uri uri) async {
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('페이지를 열지 못했습니다. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    if (!isCurrentOwner()) return;
    if (mapController?.runSession != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('진행 중인 러닝을 종료한 뒤 탈퇴할 수 있어요.')),
      );
      return;
    }
    final service =
        accountService ?? SupabaseAccountService(Supabase.instance.client);
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteAccountDialog(
        onDelete: () async {
          await service.deleteMyAccount();
          // 서버 계정이 지워진 뒤에는 기기에 남은 기록과 로그인 정보도 지웁니다.
          final map = mapController;
          if (map != null) {
            await Future.wait([
              map.runHistory.outbox.clear(),
              if (map.checkpointStore != null) map.checkpointStore!.clear(),
            ]).catchError((_) => <void>[]);
          }
          await service.signOutLocally().catchError((_) {});
        },
      ),
    );
    if (deleted == true && context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('알림 설정'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const PushSettingsScreen()),
          ),
        ),
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
        for (final (icon, title, url) in [
          (Icons.shield_outlined, '개인정보처리방침', LegalLinks.privacyPolicy),
          (Icons.description_outlined, '서비스 이용약관', LegalLinks.terms),
          (Icons.place_outlined, '위치기반서비스 이용약관', LegalLinks.locationTerms),
        ])
          if (url.isNotEmpty)
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(context, Uri.parse(url)),
            ),
        if (LegalLinks.supportEmail.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('문의하기'),
            subtitle: const Text(LegalLinks.supportEmail),
            onTap: () => _open(
              context,
              Uri(scheme: 'mailto', path: LegalLinks.supportEmail),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('오픈소스 라이선스'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(context: context),
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
                await PushService.instance.detach();
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
        ListTile(
          leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
          title: const Text('회원 탈퇴', style: TextStyle(color: Colors.red)),
          onTap: () => _deleteAccount(context),
        ),
      ],
    ),
  );
}
