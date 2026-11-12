import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../crew_controller.dart';
import '../models/crew.dart';

/// 크루 아이콘을 둥근 배지로 보여줍니다.
class CrewBadge extends StatelessWidget {
  const CrewBadge({required this.icon, this.size = 44, super.key});

  final CrewIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: icon.color.withValues(alpha: .16),
      shape: BoxShape.circle,
      border: Border.all(color: icon.color, width: 2),
    ),
    child: Icon(icon.icon, color: icon.color, size: size * .55),
  );
}

/// 크루 생성권을 쓸 때 크루 이름·설명·아이콘을 고르는 창입니다.
class CreateCrewSheet extends StatefulWidget {
  const CreateCrewSheet({required this.controller, super.key});

  final CrewController controller;

  @override
  State<CreateCrewSheet> createState() => _CreateCrewSheetState();
}

class _CreateCrewSheetState extends State<CreateCrewSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  CrewIcon? _icon;
  bool _submitted = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    final icon = _icon;
    if (!_form.currentState!.validate() || icon == null) return;
    final error = await widget.controller.create(
      _name.text.trim(),
      _description.text.trim(),
      icon,
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
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final busy = widget.controller.busy != null;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('크루 만들기', style: text.titleLarge),
                  const SizedBox(height: 4),
                  Text('크루 생성권 1개를 사용합니다.', style: text.bodySmall),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('crew-name'),
                    controller: _name,
                    maxLength: 20,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '크루 이름',
                      hintText: '예: 새벽런',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? '크루 이름은 2~20자로 입력해 주세요.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const ValueKey('crew-description'),
                    controller: _description,
                    maxLength: 60,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '크루 간단 설명 (선택)',
                      hintText: '예: 매일 아침 한강에서 5km 달려요',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('크루 아이콘', style: text.labelLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final icon in CrewIcon.values)
                        Semantics(
                          button: true,
                          selected: _icon == icon,
                          label: '크루 아이콘 ${icon.label}',
                          // 아래 글자와 겹쳐 읽히지 않게 이 라벨만 읽습니다.
                          excludeSemantics: true,
                          onTap: busy
                              ? null
                              : () => setState(() => _icon = icon),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: busy
                                ? null
                                : () => setState(() => _icon = icon),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _icon == icon
                                      ? AppColors.ink
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  ExcludeSemantics(
                                    child: CrewBadge(icon: icon, size: 48),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(icon.label, style: text.bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_submitted && _icon == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '크루 아이콘을 골라 주세요.',
                        style: TextStyle(color: AppColors.red),
                      ),
                    ),
                  if (_error case final message?)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        message,
                        style: const TextStyle(color: AppColors.red),
                      ),
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('크루 만들기'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 소셜 탭의 크루 화면입니다. 내 크루와 크루원만 보여주고, 받은 초대에 응답합니다.
class CrewTab extends StatelessWidget {
  const CrewTab({required this.controller, super.key});

  final CrewController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final text = Theme.of(context).textTheme;
      final crew = controller.crew;
      Future<void> respond(CrewInvite invite, bool accept) async {
        final error = await controller.respond(invite.crewId, accept: accept);
        if (error != null && context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(error)));
        }
      }

      return RefreshIndicator(
        onRefresh: controller.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          children: [
            if (controller.loading && controller.dashboard == null)
              const LinearProgressIndicator(),
            if (controller.error case final message?
                when controller.dashboard == null)
              Row(
                children: [
                  Expanded(child: Text(message)),
                  TextButton(
                    onPressed: controller.refresh,
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            if (controller.invites.isNotEmpty) ...[
              Text('받은 크루 초대', style: text.titleSmall),
              const SizedBox(height: 8),
              for (final invite in controller.invites)
                Card(
                  key: ValueKey('crew-invite-${invite.crewId}'),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CrewBadge(icon: invite.icon, size: 40),
                    title: Text(invite.name),
                    subtitle: Text('${invite.inviter}님의 초대'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: controller.busy == null && crew == null
                              ? () => respond(invite, false)
                              : null,
                          child: const Text('거절'),
                        ),
                        FilledButton(
                          onPressed: controller.busy == null && crew == null
                              ? () => respond(invite, true)
                              : null,
                          child: const Text('수락'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (crew != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: crew.icon.color.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    CrewBadge(icon: crew.icon, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            crew.name,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (crew.description.isNotEmpty)
                            Text(crew.description, style: text.bodySmall),
                          const SizedBox(height: 4),
                          Text(
                            '크루원 ${crew.members.length}/${crew.sizeLimit}명',
                            style: text.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '크루원 ${crew.members.length}',
                  style: text.titleSmall,
                ),
              ),
              for (final member in crew.members)
                ListTile(
                  key: ValueKey('crew-member-${member.userId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    radius: 18,
                    child: Icon(Icons.person_outline, size: 20),
                  ),
                  title: Text(member.nickname),
                  trailing: member.isOwner
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: crew.icon.color,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            child: Text(
                              '크루장',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              if (crew.isOwner)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '친구 탭에서 친구 옆의 "크루원 초대하기"를 누르면 초대할 수 있어요.',
                    style: text.bodySmall,
                  ),
                ),
            ] else if (controller.dashboard != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  '아직 크루가 없어요.\n아이템 상점에서 크루 생성권을 사서 크루를 만들 수 있어요.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
              ),
          ],
        ),
      );
    },
  );
}
