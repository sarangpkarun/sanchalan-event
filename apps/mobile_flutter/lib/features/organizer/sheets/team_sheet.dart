import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/ui_feedback.dart';
import '../../../models/members.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/error_retry.dart';
import '../../../shared/widgets/primary_button.dart';
import '../organizer_providers.dart';
import '../organizer_repository.dart';
import 'sheet_scaffold.dart';

Future<void> showTeamSheet(BuildContext context, {required String eventId, required String eventName}) =>
    showAppSheet<void>(context, (_) => TeamSheet(eventId: eventId, eventName: eventName));

/// Who is working on this event. The creator invites people with a code and decides who
/// can do what; members can leave.
class TeamSheet extends ConsumerStatefulWidget {
  const TeamSheet({super.key, required this.eventId, required this.eventName});

  final String eventId;
  final String eventName;

  @override
  ConsumerState<TeamSheet> createState() => _TeamSheetState();
}

class _TeamSheetState extends ConsumerState<TeamSheet> {
  String _inviteRole = 'editor';
  bool _busy = false;

  OrganizerRepository get _repo => ref.read(organizerRepositoryProvider);

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(eventTeamProvider(widget.eventId));
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e, fallback));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(
      text: 'Join "${widget.eventName}" on SetzO. Open the app, tap Join with code and enter: $code',
    ));
    if (mounted) showToast(context, 'Invite copied');
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(eventTeamProvider(widget.eventId));
    return SheetFrame(
      title: 'Team',
      subtitle: widget.eventName,
      children: [
        team.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(eventTeamProvider(widget.eventId))),
          data: _content,
        ),
      ],
    );
  }

  Widget _content(EventTeam t) {
    final text = Theme.of(context).textTheme;
    final company = t.ownerType == 'company';
    final me = t.members.where((m) => m.role == t.myRole).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpace.m),
        for (final m in t.members)
          _MemberRow(
            member: m,
            canManage: t.isOwner && m.role != 'owner',
            busy: _busy,
            onRole: (r) => _run(() => _repo.updateMember(widget.eventId, m.userId, role: r), 'Could not change the role.'),
            onApprove: () => _run(() => _repo.updateMember(widget.eventId, m.userId, approve: true), 'Could not approve.'),
            onRemove: () async {
              final yes = await showConfirmDialog(
                context,
                title: m.pending ? 'Decline request?' : 'Remove ${m.name ?? 'this person'}?',
                message: 'They will no longer see this event.',
                confirmLabel: m.pending ? 'Decline' : 'Remove',
                destructive: true,
              );
              if (yes) await _run(() => _repo.removeMember(widget.eventId, m.userId), 'Could not remove.');
            },
          ),
        if (t.isOwner) ...[
          const Divider(height: AppSpace.xl),
          Text('Invite someone', style: text.titleSmall),
          const SizedBox(height: AppSpace.xs),
          Text(
            company
                ? 'People who join need your approval before they can see anything.'
                : 'Anyone with the code joins straight away.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpace.s),
          Wrap(
            spacing: AppSpace.s,
            children: [
              for (final r in const ['editor', 'approver', 'viewer'])
                ChoiceChip(
                  label: Text(memberRoleLabel(r)),
                  selected: _inviteRole == r,
                  onSelected: (_) => setState(() => _inviteRole = r),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(memberRoleHint(_inviteRole), style: text.bodySmall),
          ),
          const SizedBox(height: AppSpace.m),
          SecondaryButton(
            label: 'Create invite code',
            icon: Icons.person_add_alt_1_outlined,
            onPressed: _busy
                ? null
                : () => _run(() async {
                      final invite = await _repo.createInvite(widget.eventId, _inviteRole);
                      await _copy(invite.code);
                    }, 'Could not create the invite. Complete your profile type first.'),
          ),
          for (final i in t.invites)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(i.code, style: text.titleMedium?.copyWith(letterSpacing: 2)),
              subtitle: Text('${memberRoleLabel(i.role)} · expires ${i.expiresAt.toLocal().toString().substring(0, 10)}'),
              trailing: Wrap(
                children: [
                  IconButton(tooltip: 'Copy invite', icon: const Icon(Icons.copy), onPressed: () => _copy(i.code)),
                  IconButton(
                    tooltip: 'Revoke invite',
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => _run(() => _repo.revokeInvite(widget.eventId, i.id), 'Could not revoke.'),
                  ),
                ],
              ),
            ),
        ] else if (me != null || t.myRole != 'owner') ...[
          const SizedBox(height: AppSpace.l),
          TextButton.icon(
            onPressed: _busy ? null : () => _leave(),
            icon: const Icon(Icons.logout),
            label: const Text('Leave this event'),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorText),
          ),
        ],
      ],
    );
  }

  Future<void> _leave() async {
    final yes = await showConfirmDialog(
      context,
      title: 'Leave this event?',
      message: 'You will need a new invite to come back.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!yes || !mounted) return;
    final me = ref.read(organizerDataProvider).value;
    if (me is! OrganizerReady) return;
    await _run(() => _repo.removeMember(widget.eventId, me.organizer.id), 'Could not leave.');
    await ref.read(organizerDataProvider.notifier).reloadEvents();
    if (mounted) Navigator.of(context).pop();
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.canManage,
    required this.busy,
    required this.onRole,
    required this.onApprove,
    required this.onRemove,
  });

  final EventMember member;
  final bool canManage;
  final bool busy;
  final ValueChanged<String> onRole;
  final VoidCallback onApprove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final name = member.name ?? member.phoneNumber ?? 'Member';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.maroonContainer,
        child: Text(name.characters.first.toUpperCase(), style: const TextStyle(color: AppColors.maroon)),
      ),
      title: Text(name),
      subtitle: Text(member.pending ? 'Waiting for approval' : memberRoleLabel(member.role)),
      trailing: !canManage
          ? null
          : member.pending
              ? Wrap(children: [
                  IconButton(tooltip: 'Approve', icon: const Icon(Icons.check_circle_outline), onPressed: busy ? null : onApprove),
                  IconButton(tooltip: 'Decline', icon: const Icon(Icons.cancel_outlined), onPressed: busy ? null : onRemove),
                ])
              : PopupMenuButton<String>(
                  tooltip: 'Change role for $name',
                  onSelected: (v) => v == 'remove' ? onRemove() : onRole(v),
                  itemBuilder: (_) => [
                    for (final r in const ['editor', 'approver', 'viewer'])
                      PopupMenuItem(value: r, child: Text('Make ${memberRoleLabel(r).toLowerCase()}')),
                    const PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                ),
    );
  }
}
