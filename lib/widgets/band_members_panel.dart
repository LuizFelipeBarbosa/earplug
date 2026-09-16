import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_sheet.dart';
import 'ep_text.dart';
import 'sheets.dart';

const _searchDebounce = Duration(milliseconds: 250);

class BandMembersPanel extends StatelessWidget {
  const BandMembersPanel({super.key, required this.bandId});

  final String bandId;

  @override
  Widget build(BuildContext context) =>
      _BandMembersPanelBody(key: ValueKey(bandId), bandId: bandId);
}

class _BandMembersPanelBody extends StatefulWidget {
  const _BandMembersPanelBody({super.key, required this.bandId});

  final String bandId;

  @override
  State<_BandMembersPanelBody> createState() => _BandMembersPanelBodyState();
}

class _BandMembersPanelBodyState extends State<_BandMembersPanelBody> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  String _query = '';
  bool _working = false;
  String? _inviteError;
  String? _loadedBandId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final id = widget.bandId;
    if (id.isEmpty || _loadedBandId == id) return;
    _loadedBandId = id;
    Future.microtask(() {
      app.refreshBandInvite(id);
      app.refreshBandMembers(id);
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Invite failures stay on the panel so the admin can retry in place.
  Future<void> _runInviteAction(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _inviteError = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() {
          _inviteError = 'The invitation could not be updated. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // AppState toasts member failures itself and re-renders the list from
  // state; the panel only tracks the busy line.
  Future<void> _runMemberAction(Future<void> Function() action) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchTimer?.cancel();
    final app = context.read<AppState>();
    if (value.trim().length < 2) {
      app.searchPeople('');
      return;
    }
    _searchTimer = Timer(_searchDebounce, () => app.searchPeople(value));
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchController.clear();
    setState(() => _query = '');
    context.read<AppState>().searchPeople('');
  }

  Future<void> _addMember(AppState app, String userId) async {
    await _runMemberAction(() => app.addBandMember(widget.bandId, userId));
    if (!mounted) return;
    final added =
        app
            .bandMembersFor(widget.bandId)
            ?.any((member) => member.userId == userId) ??
        false;
    if (added) _clearSearch();
  }

  void _showMemberActions(
    AppState app,
    BandMember member, {
    required bool viewerIsAdmin,
    required bool isLastAdmin,
  }) {
    final bandName = app.band(widget.bandId)?.name ?? 'this band';
    final items = <EpActionSheetItem>[
      if (viewerIsAdmin && !member.isSelf && !isLastAdmin)
        EpActionSheetItem(
          label: member.role == BandMemberRole.admin
              ? 'Make member'
              : 'Make admin',
          icon: Icons.admin_panel_settings_outlined,
          onPressed: () => _runMemberAction(
            () => app.setBandMemberRole(
              widget.bandId,
              member.userId,
              member.role == BandMemberRole.admin
                  ? BandMemberRole.member
                  : BandMemberRole.admin,
            ),
          ),
        ),
      if (member.isSelf)
        EpActionSheetItem(
          label: 'Leave band',
          icon: Icons.logout,
          destructive: true,
          onPressed: () => _confirmRemoval(
            app,
            member,
            header: 'Leave $bandName?',
            confirmLabel: 'LEAVE',
          ),
        )
      else if (viewerIsAdmin)
        EpActionSheetItem(
          label: 'Remove',
          icon: Icons.person_remove_alt_1_outlined,
          destructive: true,
          onPressed: () => _confirmRemoval(
            app,
            member,
            header: 'Remove ${member.name}?',
            confirmLabel: 'REMOVE',
          ),
        ),
    ];
    showEpActionSheet(context, header: member.name, items: items);
  }

  void _confirmRemoval(
    AppState app,
    BandMember member, {
    required String header,
    required String confirmLabel,
  }) {
    showEpSheet(
      context,
      (_) => _ConfirmSheet(
        header: header,
        confirmLabel: confirmLabel,
        onConfirm: () => _runMemberAction(
          () => app.removeBandMember(widget.bandId, member.userId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final palette = context.epColors;
    final id = widget.bandId;
    final isAdmin = app.isAdminOf(id);
    final members = app.bandMembersFor(id);
    final loaded = members ?? const <BandMember>[];
    final memberIds = {for (final member in loaded) member.userId};
    final adminCount = loaded
        .where((member) => member.role == BandMemberRole.admin)
        .length;
    final invite = app.inviteFor(id);
    final activeInvite = invite != null && !invite.revoked && !invite.expired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: EpEyebrow('Band members')),
            const SizedBox(width: 12),
            EpMonoText(
              '${members?.length ?? 0}',
              key: const ValueKey('band-members-count'),
              color: palette.muted,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_working)
          LinearProgressIndicator(
            minHeight: 2,
            color: palette.accent,
            backgroundColor: Colors.transparent,
          )
        else
          const EpHairline(),
        if (isAdmin) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: EpUnderlineField(
                  fieldKey: const Key('band-members-search'),
                  controller: _searchController,
                  hint: 'Add by name',
                  icon: Icons.person_add_alt_1_outlined,
                  textInputAction: TextInputAction.search,
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              EpPill(
                key: const Key('band-members-generate-link'),
                label: invite == null ? 'Generate link' : 'New link',
                icon: Icons.link,
                onPressed: _working
                    ? null
                    : () => _runInviteAction(() async {
                        await app.createBandInvitation();
                      }),
              ),
            ],
          ),
          if (_query.trim().length >= 2)
            _SearchResults(
              results: app.peopleResults,
              searching: app.peopleSearching,
              memberIds: memberIds,
              working: _working,
              onAdd: (userId) => _addMember(app, userId),
            ),
        ],
        const SizedBox(height: 8),
        if (members == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: EpMonoText('LOADING…', color: palette.muted),
          )
        else
          for (final member in members)
            _MemberRow(
              key: ValueKey('band-member-${member.userId}'),
              member: member,
              showActions: isAdmin || member.isSelf,
              onActions: () => _showMemberActions(
                app,
                member,
                viewerIsAdmin: isAdmin,
                isLastAdmin:
                    member.role == BandMemberRole.admin && adminCount <= 1,
              ),
            ),
        if (isAdmin && invite != null) ...[
          const SizedBox(height: 20),
          if (activeInvite)
            _InviteBlock(
              invite: invite,
              working: _working,
              onRotate: () => _runInviteAction(() async {
                await app.rotateBandInvitation();
              }),
              onRevoke: () => _runInviteAction(app.revokeBandInvitation),
            )
          else
            Text(
              invite.revoked
                  ? 'The previous invitation was revoked.'
                  : 'The previous invitation expired.',
              style: Theme.of(context).textTheme.epCaption.copyWith(
                fontSize: 11,
                color: palette.muted,
              ),
            ),
        ],
        if (_inviteError case final error?) ...[
          const SizedBox(height: 8),
          Text(
            error,
            key: const ValueKey('invite-management-error'),
            style: Theme.of(context).textTheme.epCaption.copyWith(
              fontSize: 11,
              color: palette.warning,
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.results,
    required this.searching,
    required this.memberIds,
    required this.working,
    required this.onAdd,
  });

  final List<SocialUserCard> results;
  final bool searching;
  final Set<String> memberIds;
  final bool working;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: EpMonoText(
          searching ? 'SEARCHING…' : 'No one found',
          color: context.epColors.muted,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final person in results)
          EpEntityRow(
            key: ValueKey('band-members-result-${person.userId}'),
            leading: EpFanAvatar(
              name: person.name,
              imageUrl: person.avatarUrl,
              size: 32,
            ),
            title: person.name,
            sub: memberIds.contains(person.userId) ? 'Already a member' : null,
            trailing: EpPill(
              key: ValueKey('band-members-add-${person.userId}'),
              label: 'Add',
              variant: EpPillVariant.primary,
              onPressed: working || memberIds.contains(person.userId)
                  ? null
                  : () => onAdd(person.userId),
            ),
          ),
      ],
    );
  }
}

/// Mirrors [EpEntityRow]'s grammar with a role pill under the name, which the
/// shared row cannot host in its text-only subtitle.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.member,
    required this.showActions,
    required this.onActions,
  });

  final BandMember member;
  final bool showActions;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                EpFanAvatar(
                  name: member.name,
                  imageUrl: member.avatarUrl,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EpDisplay(member.name, size: 20, maxLines: 1),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          StatusPill(
                            label: member.role.label.toUpperCase(),
                            tone: member.role == BandMemberRole.admin
                                ? EpStatusPillTone.selected
                                : EpStatusPillTone.neutral,
                          ),
                          if (member.isSelf) ...[
                            const SizedBox(width: 6),
                            EpMonoText('· You', color: palette.muted),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (showActions) ...[
                  const SizedBox(width: 12),
                  EpIconPill(
                    key: ValueKey('band-member-actions-${member.userId}'),
                    icon: Icons.more_horiz,
                    semanticLabel: 'Actions for ${member.name}',
                    onPressed: onActions,
                  ),
                ],
              ],
            ),
          ),
        ),
        const EpHairline(),
      ],
    );
  }
}

class _InviteBlock extends StatelessWidget {
  const _InviteBlock({
    required this.invite,
    required this.working,
    required this.onRotate,
    required this.onRevoke,
  });

  final BandInvite invite;
  final bool working;
  final VoidCallback onRotate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final expires = invite.expiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpEyebrow('Invitation link · expires ${expires.month}/${expires.day}'),
        const SizedBox(height: 8),
        SelectableText(
          invite.url,
          key: const ValueKey('band-invite-url'),
          style: Theme.of(context).textTheme.epBody.copyWith(fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EpPill(
              key: const Key('band-invite-copy'),
              label: 'Copy',
              icon: Icons.copy,
              onPressed: working
                  ? null
                  : () => copyForUser(
                      context,
                      invite.url,
                      successMessage: 'Invitation link copied.',
                    ),
            ),
            EpPill(
              key: const Key('band-invite-rotate'),
              label: 'Rotate',
              icon: Icons.autorenew,
              onPressed: working ? null : onRotate,
            ),
            EpPill(
              key: const Key('band-invite-revoke'),
              label: 'Revoke',
              icon: Icons.link_off,
              onPressed: working ? null : onRevoke,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'One secure link, valid seven days, usable by several members.',
          style: Theme.of(context).textTheme.epCaption,
        ),
      ],
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({
    required this.header,
    required this.confirmLabel,
    required this.onConfirm,
  });

  final String header;
  final String confirmLabel;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return EpSheetShell(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      backgroundColor: context.epColors.raised,
      borderColor: context.epColors.border,
      topRadius: EpLayout.cardRadius,
      handleColor: context.epColors.mute,
      handleBottomSpacing: 14,
      mainAxisSize: MainAxisSize.min,
      header: Text(
        header.toUpperCase(),
        semanticsLabel: header,
        style: Theme.of(context).textTheme.epSectionHeading,
      ),
      children: [
        const SizedBox(height: 16),
        OutlinedButton(
          key: const Key('band-member-confirm'),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.epColors.destructive,
          ),
          onPressed: () async {
            await onConfirm();
            if (!context.mounted) return;
            Navigator.pop(context);
          },
          child: Text(confirmLabel),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('KEEP'),
        ),
      ],
    );
  }
}
