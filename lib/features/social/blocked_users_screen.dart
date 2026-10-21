import 'package:flutter/material.dart';

import '../../shared/widgets/account_query_panel.dart';
import 'data/block_service.dart';
import 'widgets/block_button.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({required this.service, super.key});
  final BlockService service;

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('차단한 사용자')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AccountQueryPanel<List<BlockedUser>>(
        source: widget.service,
        load: widget.service.load,
        isCurrentOwner: () => widget.service.isCurrentOwner,
        revision: _revision,
        errorMessage: '차단 목록을 불러오지 못했습니다.',
        builder: (context, users) => Column(
          children: [
            if (users.isEmpty) const Text('차단한 사용자가 없습니다.'),
            for (final user in users)
              ListTile(
                title: Text(user.nickname),
                trailing: BlockButton(
                  service: widget.service,
                  userId: user.id,
                  nickname: user.nickname,
                  blocked: true,
                  onChanged: () => setState(() => _revision++),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
