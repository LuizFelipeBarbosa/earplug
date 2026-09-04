import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

class OrgTeamScreen extends StatefulWidget {
  const OrgTeamScreen({super.key});

  @override
  State<OrgTeamScreen> createState() => _OrgTeamScreenState();
}

class _OrgTeamScreenState extends State<OrgTeamScreen> {
  List<OrganizationMember> _members = const [];
  OrganizationInvite? _invite;
  Object? _membersError;
  Object? _inviteError;
  bool _membersLoading = true;
  bool _inviteLoading = true;
  bool _inviteWorking = false;
  OrganizationRole _selectedInviteRole = OrganizationRole.manager;
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

  Future<void> _refreshInvite() async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() {
      _inviteLoading = true;
      _inviteError = null;
    });
    try {
      final invite = await app.repository.organizationInvite(organizationId);
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _invite = invite;
        _inviteLoading = false;
      });
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() {
        _inviteError = error;
        _inviteLoading = false;
      });
    }
  }

  void _showMemberActions(OrganizationMember member) {
    showEpActionSheet(
      context,
      header: member.name,
      items: [
        EpActionSheetItem(
          label: 'CHANGE ROLE',
          icon: Icons.manage_accounts_outlined,
          onPressed: () => _showRoleSheet(member),
        ),
        EpActionSheetItem(
          label: 'REMOVE',
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
            label: _roleLabel(role).toUpperCase(),
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
      if (mounted) app.say(_errorMessage(error));
    }
  }

  Future<void> _confirmRemove(OrganizationMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${member.name}?'),
        content: const Text(
          'They will lose access to this organization and its management tools.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final app = context.read<AppState>();
    try {
      await app.repository.removeOrganizationMember(
        organizationId: app.organizationId,
        userId: member.userId,
      );
      await _refreshMembers();
      if (mounted) app.say('Member removed.');
    } catch (error) {
      if (mounted) app.say(_errorMessage(error));
    }
  }

  Future<void> _createInvite() async {
    if (_inviteWorking) return;
    final app = context.read<AppState>();
    setState(() => _inviteWorking = true);
    try {
      final invite = await app.repository.createOrganizationInvite(
        organizationId: app.organizationId,
        role: _selectedInviteRole,
      );
      if (mounted) setState(() => _invite = invite);
    } catch (_) {
      if (mounted) {
        app.say('The invitation could not be updated. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _inviteWorking = false);
    }
  }

  Future<void> _rotateInvite() async {
    if (_inviteWorking) return;
    final app = context.read<AppState>();
    setState(() => _inviteWorking = true);
    try {
      await app.repository.rotateOrganizationInvite(app.organizationId);
      await _refreshInvite();
    } catch (_) {
      if (mounted) {
        app.say('The invitation could not be updated. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _inviteWorking = false);
    }
  }

  Future<void> _revokeInvite() async {
    if (_inviteWorking) return;
    final app = context.read<AppState>();
    setState(() => _inviteWorking = true);
    try {
      await app.repository.revokeOrganizationInvite(app.organizationId);
      await _refreshInvite();
    } catch (_) {
      if (mounted) {
        app.say('The invitation could not be updated. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _inviteWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final isOwner =
        app.organizerRoleFor(app.organizationId) == OrganizationRole.owner;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Text('TEAM', style: epDisplay(size: 22)),
        const SizedBox(height: 4),
        Text(
          'Manage who can operate this organization.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        SectionBar(label: 'MEMBERS', count: _members.length),
        if (_membersLoading)
          const Center(child: CircularProgressIndicator())
        else if (_membersError != null)
          _LoadError(
            label: 'Could not load team members.',
            onRetry: _refreshMembers,
          )
        else if (_members.isEmpty)
          const EpCard(child: Text('No organization members found.'))
        else
          EpCard(
            variant: EpCardVariant.raised,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var index = 0; index < _members.length; index++) ...[
                  _MemberRow(
                    key: ValueKey('org-team-member-${_members[index].userId}'),
                    member: _members[index],
                    onTap: isOwner
                        ? () => _showMemberActions(_members[index])
                        : null,
                  ),
                  if (index < _members.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        if (isOwner) ...[
          const SectionBar(label: 'INVITE'),
          Text(
            'Create one secure link for a manager, finance, or door role. It can be used for seven days.',
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 12),
          EpCard(
            variant: EpCardVariant.raised,
            padding: const EdgeInsets.all(15),
            child: _inviteSection(context),
          ),
        ],
      ],
    );
  }

  Widget _inviteSection(BuildContext context) {
    if (_inviteLoading && _invite == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_inviteError != null && _invite == null) {
      return _LoadError(
        label: 'Could not load the current invitation.',
        onRetry: _refreshInvite,
      );
    }

    final active = _invite != null && !_invite!.revoked && !_invite!.expired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'INVITED ROLE',
          style: Theme.of(context).textTheme.epLabel.copyWith(
            fontSize: 11,
            color: context.epColors.contentSecondary,
          ),
        ),
        const SizedBox(height: 5),
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
                label: _roleLabel(role),
                active: _selectedInviteRole == role,
                onTap: _inviteWorking
                    ? null
                    : () => setState(() => _selectedInviteRole = role),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (!active) ...[
          if (_invite != null) ...[
            Text(
              _invite!.revoked
                  ? 'The previous invitation was revoked.'
                  : 'The previous invitation expired.',
              style: Theme.of(context).textTheme.epCaption,
            ),
            const SizedBox(height: 8),
          ],
          EpButton(
            _invite == null ? 'CREATE LINK' : 'CREATE NEW LINK',
            key: const Key('org-team-invite-create'),
            kind: _inviteWorking ? EpButtonKind.disabled : EpButtonKind.outline,
            onTap: _inviteWorking ? null : _createInvite,
          ),
        ] else ...[
          Builder(
            builder: (context) {
              final invite = _invite!;
              final link = '$publicWebOrigin/apply/${invite.token}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EpCard(
                    variant: EpCardVariant.selected,
                    padding: const EdgeInsets.all(11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(
                          link,
                          style: epText(size: 11.5, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'ACTIVE · EXPIRES ${_expiryLabel(invite.expiresAt)}',
                          style: epText(
                            size: 11,
                            weight: FontWeight.w800,
                            color: context.epColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const Key('org-team-invite-copy'),
                    onPressed: _inviteWorking
                        ? null
                        : () => copyForUser(
                            context,
                            link,
                            successMessage: 'Invitation link copied.',
                          ),
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text('COPY INVITATION LINK'),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('org-team-invite-rotate'),
                          onPressed: _inviteWorking ? null : _rotateInvite,
                          child: const Text('ROTATE LINK'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('org-team-invite-revoke'),
                          onPressed: _inviteWorking ? null : _revokeInvite,
                          child: const Text('REVOKE LINK'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
        if (_inviteWorking) ...[
          const SizedBox(height: 9),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({super.key, required this.member, required this.onTap});

  final OrganizationMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final email = member.email?.trim();
    return LedgerRow(
      title: member.name,
      details: [if (email != null && email.isNotEmpty) email],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(
            label: _roleLabel(member.role),
            tone: EpStatusPillTone.neutral,
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.more_horiz, color: context.epColors.contentSecondary),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.label, required this.onRetry});

  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.epBody),
        const SizedBox(height: 8),
        EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
      ],
    );
  }
}

String _roleLabel(OrganizationRole role) => switch (role) {
  OrganizationRole.owner => 'Owner',
  OrganizationRole.manager => 'Manager',
  OrganizationRole.finance => 'Finance',
  OrganizationRole.door => 'Door',
};

String _expiryLabel(DateTime date) => '${date.month}/${date.day}/${date.year}';

String _errorMessage(Object error) =>
    error.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');
