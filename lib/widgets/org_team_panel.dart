import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_sheet.dart';
import 'ep_text.dart';
import 'form_bits.dart';
import 'opportunity_labels.dart';
import 'sheets.dart';

/// The organization's TEAM section: one entity row per member with the
/// owner-only Change role / Remove overflow, and an "Invite a teammate" row
/// that opens the invite-link sheet. Shared by the ORGANIZATION hub and the
/// standalone team screen.
class OrgTeamPanel extends StatefulWidget {
  const OrgTeamPanel({super.key});

  @override
  State<OrgTeamPanel> createState() => _OrgTeamPanelState();
}

class _OrgTeamPanelState extends State<OrgTeamPanel> {
  List<OrganizationMember> _members = const [];
  OrganizationInvite? _invite;
  Object? _membersError;
  bool _membersLoading = true;
  String? _loadedOrganizationId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final organizationId = context.read<AppState>().organizationId;
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _members = const [];
    _invite = null;
    _refreshMembers();
    _refreshInvite();
  }

  Future<void> _refreshMembers() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _membersLoading = true;
      _membersError = null;
    });
    try {
      final members = await app.repository.organizationMembers(organizationId);
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _members = members;
        _membersLoading = false;
      });
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _membersError = error;
        _membersLoading = false;
      });
    }
  }

  // The invite only decorates the invite row here; the sheet owns its
  // create/rotate/revoke flow and reports the result back.
  Future<void> _refreshInvite() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    try {
      final invite = await app.repository.organizationInvite(organizationId);
      if (!mounted || app.organizationId != organizationId) return;
      setState(() => _invite = invite);
    } catch (_) {
      // The sheet starts from "no link" and can still create one.
    }
  }

  void _showMemberActions(OrganizationMember member) {
    showEpActionSheet(
      context,
      header: member.name,
      items: [
        EpActionSheetItem(
          label: 'Change role',
          icon: Icons.manage_accounts_outlined,
          onPressed: () => _showRoleSheet(member),
        ),
        EpActionSheetItem(
          label: 'Remove',
          icon: Icons.person_remove_outlined,
          destructive: true,
          onPressed: () => _confirmRemove(member),
        ),
      ],
    );
  }

  void _showRoleSheet(OrganizationMember member) {
    showEpActionSheet(
      context,
      header: 'Change ${member.name}\'s role',
      items: [
        for (final role in OrganizationRole.values)
          EpActionSheetItem(
            label: organizationRoleLabel(role),
            icon: role == member.role
                ? Icons.check_circle_outline
                : Icons.circle_outlined,
            onPressed: () => _changeRole(member, role),
          ),
      ],
    );
  }

  Future<void> _changeRole(
    OrganizationMember member,
    OrganizationRole role,
  ) async {
    final app = context.read<AppState>();
    try {
      await app.repository.setOrganizationMemberRole(
        organizationId: app.organizationId,
        userId: member.userId,
        role: role,
      );
      await _refreshMembers();
      if (mounted) app.say('Role updated.');
    } catch (error) {
      if (mounted) app.say(stripStateErrorPrefix(error));
    }
  }

  Future<void> _confirmRemove(OrganizationMember member) async {
    final confirmed = await epConfirm(
      context,
      title: 'Remove ${member.name}?',
      body:
          'They will lose access to this organization and its management tools.',
      keepLabel: 'CANCEL',
      confirmLabel: 'REMOVE',
    );
    if (!confirmed || !mounted) return;

    final app = context.read<AppState>();
    try {
      await app.repository.removeOrganizationMember(
        organizationId: app.organizationId,
        userId: member.userId,
      );
      await _refreshMembers();
      if (mounted) app.say('Member removed.');
    } catch (error) {
      if (mounted) app.say(stripStateErrorPrefix(error));
    }
  }

  void _showInviteSheet() {
    showEpSheet(
      context,
      (_) => _InviteSheet(
        key: const Key('org-hub-invite-sheet'),
        initialInvite: _invite,
        onInviteChanged: (invite) {
          if (mounted) setState(() => _invite = invite);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final palette = context.epColors;
    final isOwner =
        app.organizerRoleFor(app.organizationId) == OrganizationRole.owner;
    final invite = _invite;
    final activeInvite = invite != null && !invite.revoked && !invite.expired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: EpEyebrow('Team')),
            const SizedBox(width: 12),
            EpMonoText(
              'Members · ${_members.length}',
              key: const Key('org-hub-members-count'),
              color: palette.muted,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const EpHairline(),
        if (_membersLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: EpMonoText('Loading…', color: palette.muted),
          )
        else if (_membersError != null)
          _LoadError(
            label: 'Could not load team members.',
            onRetry: _refreshMembers,
          )
        else if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: EpMonoText('No members yet', color: palette.muted),
          )
        else
          for (final member in _members)
            _MemberRow(
              key: ValueKey('org-hub-member-${member.userId}'),
              member: member,
              onActions: isOwner ? () => _showMemberActions(member) : null,
            ),
        if (isOwner)
          EpMenuRow(
            key: const Key('org-hub-invite'),
            icon: Icons.person_add_outlined,
            label: 'Invite a teammate',
            sub: activeInvite
                ? 'Link active · expires ${_expiryLabel(invite.expiresAt)}'
                : null,
            onTap: _showInviteSheet,
          ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({super.key, required this.member, required this.onActions});

  final OrganizationMember member;
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) {
    final email = member.email?.trim();
    return EpEntityRow(
      leading: EpFanAvatar(name: member.name, size: 40),
      title: member.name,
      sub: email == null || email.isEmpty ? null : email,
      subMaxLinesOne: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(
            label: organizationRoleLabel(member.role),
            tone: member.role == OrganizationRole.owner
                ? EpStatusPillTone.selected
                : EpStatusPillTone.neutral,
          ),
          if (onActions != null) ...[
            const SizedBox(width: 8),
            EpIconPill(
              key: ValueKey('org-hub-member-actions-${member.userId}'),
              icon: Icons.more_horiz,
              semanticLabel: 'Actions for ${member.name}',
              onPressed: onActions,
            ),
          ],
        ],
      ),
    );
  }
}

/// Role picker plus the single invite link: create, copy, rotate, revoke.
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({
    super.key,
    required this.initialInvite,
    required this.onInviteChanged,
  });

  final OrganizationInvite? initialInvite;
  final ValueChanged<OrganizationInvite?> onInviteChanged;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  late OrganizationInvite? _invite = widget.initialInvite;
  OrganizationRole _selectedRole = OrganizationRole.manager;
  bool _working = false;
  String? _error;

  Future<void> _run(Future<OrganizationInvite?> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final invite = await action();
      if (!mounted) return;
      setState(() => _invite = invite);
      widget.onInviteChanged(invite);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'The invitation could not be updated. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _create() {
    final app = context.read<AppState>();
    _run(
      () => app.repository.createOrganizationInvite(
        organizationId: app.organizationId,
        role: _selectedRole,
      ),
    );
  }

  void _rotate() {
    final app = context.read<AppState>();
    _run(() async {
      await app.repository.rotateOrganizationInvite(app.organizationId);
      return app.repository.organizationInvite(app.organizationId);
    });
  }

  void _revoke() {
    final app = context.read<AppState>();
    _run(() async {
      await app.repository.revokeOrganizationInvite(app.organizationId);
      return app.repository.organizationInvite(app.organizationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final textTheme = Theme.of(context).textTheme;
    final invite = _invite;
    final active = invite != null && !invite.revoked && !invite.expired;

    return EpFormSheet(
      title: 'Invite a teammate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'One secure link for a manager, finance, or door role. It can be '
            'used for seven days.',
            style: textTheme.epCaption,
          ),
          const SizedBox(height: 16),
          const EpEyebrow('Invited role'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final role in const [
                OrganizationRole.manager,
                OrganizationRole.finance,
                OrganizationRole.door,
              ])
                EpChip(
                  key: ValueKey('org-team-invite-role-${role.wireValue}'),
                  label: organizationRoleLabel(role),
                  active: _selectedRole == role,
                  onTap: _working
                      ? null
                      : () => setState(() => _selectedRole = role),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (!active) ...[
            if (invite != null) ...[
              Text(
                invite.revoked
                    ? 'The previous invitation was revoked.'
                    : 'The previous invitation expired.',
                style: textTheme.epCaption,
              ),
              const SizedBox(height: 8),
            ],
            EpPill(
              key: const Key('org-team-invite-create'),
              label: invite == null ? 'Create link' : 'Create new link',
              variant: EpPillVariant.primary,
              size: EpPillSize.regular,
              expand: true,
              onPressed: _working ? null : _create,
            ),
          ] else ...[
            EpEyebrow(
              'Invitation link · expires ${_expiryLabel(invite.expiresAt)}',
            ),
            const SizedBox(height: 8),
            SelectableText(
              '$publicWebOrigin/apply/${invite.token}',
              key: const Key('org-team-invite-link'),
              style: textTheme.epInviteUrl,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                EpPill(
                  key: const Key('org-team-invite-copy'),
                  label: 'Copy',
                  icon: Icons.copy,
                  onPressed: _working
                      ? null
                      : () => copyForUser(
                          context,
                          '$publicWebOrigin/apply/${invite.token}',
                          successMessage: 'Invitation link copied.',
                        ),
                ),
                EpPill(
                  key: const Key('org-team-invite-rotate'),
                  label: 'Rotate',
                  icon: Icons.autorenew,
                  onPressed: _working ? null : _rotate,
                ),
                EpPill(
                  key: const Key('org-team-invite-revoke'),
                  label: 'Revoke',
                  icon: Icons.link_off,
                  onPressed: _working ? null : _revoke,
                ),
              ],
            ),
          ],
          if (_working) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              minHeight: 2,
              color: palette.accent,
              backgroundColor: Colors.transparent,
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              key: const Key('org-team-invite-error'),
              style: textTheme.epCaption.copyWith(color: palette.destructive),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.label, required this.onRetry});

  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.epBody),
          ),
          const SizedBox(width: 12),
          EpPill(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

String _expiryLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';
