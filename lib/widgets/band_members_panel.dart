import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'form_bits.dart';

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
  bool _working = false;
  String? _error;
  String? _loadedBandId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final id = widget.bandId;
    if (id.isEmpty || _loadedBandId == id) return;
    _loadedBandId = id;
    Future.microtask(() => app.refreshBandInvite(id));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'The invitation could not be updated. Please retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _expiryLabel(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final id = widget.bandId;
    final invite = app.inviteFor(id);
    final loading = app.inviteLoadingFor(id);
    final members = app.profileDetailsFor(id)?.memberNames ?? const [];
    final active = invite != null && !invite.revoked && !invite.expired;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EpSectionHeader(
          label: 'BAND MEMBERS · ${members.length}',
          padding: const EdgeInsets.only(bottom: 6),
        ),
        Text(
          'One secure link, valid seven days, usable by several members.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SizedBox(height: 14),
        const FieldLabel('ACCEPTED MEMBERS'),
        const SizedBox(height: 7),
        if (members.isEmpty)
          Text(
            'No additional members have joined yet.',
            style: Theme.of(
              context,
            ).textTheme.epCaption.copyWith(fontSize: 11.5),
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final member in members)
                EpChip(
                  key: ValueKey('accepted-member-$member'),
                  label: member,
                  active: false,
                  onTap: null,
                  semanticLabel: '$member, accepted member',
                ),
            ],
          ),
        const SizedBox(height: 10),
        if (loading && invite == null)
          const Center(child: CircularProgressIndicator())
        else if (!active) ...[
          if (invite != null)
            Text(
              invite.revoked
                  ? 'The previous invitation was revoked.'
                  : 'The previous invitation expired.',
              style: Theme.of(
                context,
              ).textTheme.epCaption.copyWith(fontSize: 11),
            ),
          if (invite != null) const SizedBox(height: 8),
          EpButton(
            invite == null
                ? 'CREATE INVITATION LINK'
                : 'CREATE NEW INVITATION LINK',
            kind: _working ? EpButtonKind.disabled : EpButtonKind.outline,
            onTap: _working
                ? null
                : () => _run(() async {
                    await app.createBandInvitation();
                  }),
          ),
        ] else ...[
          EpCard(
            variant: EpCardVariant.selected,
            padding: const EdgeInsets.all(11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  invite.url,
                  key: const ValueKey('band-invite-url'),
                  style: Theme.of(
                    context,
                  ).textTheme.epBody.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 7),
                Text(
                  'ACTIVE · EXPIRES ${_expiryLabel(invite.expiresAt)}',
                  style: Theme.of(context).textTheme.epChipLabel.copyWith(
                    color: context.epColors.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _working
                ? null
                : () => copyForUser(
                    context,
                    invite.url,
                    successMessage: 'Invitation link copied.',
                  ),
            icon: Icon(Icons.copy, size: 17),
            label: Text('COPY INVITATION LINK'),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _working
                      ? null
                      : () => _run(() async {
                          await app.rotateBandInvitation();
                        }),
                  child: Text('ROTATE LINK'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _working
                      ? null
                      : () => _run(app.revokeBandInvitation),
                  child: Text('REVOKE LINK'),
                ),
              ),
            ],
          ),
        ],
        if (_working) ...[
          const SizedBox(height: 9),
          const LinearProgressIndicator(),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 8),
          Text(
            error,
            key: const ValueKey('invite-management-error'),
            style: Theme.of(context).textTheme.epCaption.copyWith(
              fontSize: 11,
              color: context.epColors.warning,
            ),
          ),
        ],
      ],
    );
  }
}
