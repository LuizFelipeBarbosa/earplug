import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class GigInviteScreen extends StatelessWidget {
  const GigInviteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return ColoredBox(
      color: context.epColors.background,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: Icons.close,
                    onTap: app.canGoBack ? app.back : app.toFanView,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'LINEUP INVITATION',
                      style: epDisplay(size: 16),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.epColors.border),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _body(app),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(AppState app) {
    if (app.performerInviteLoading) {
      return const Column(
        key: ValueKey('performer-invite-loading'),
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('CHECKING INVITATION…'),
        ],
      );
    }
    if (app.performerInviteClaimed) {
      return _Claimed(
        key: const ValueKey('performer-invite-claimed'),
        invite: app.performerInvite,
        onManager: app.openClaimedGigManager,
      );
    }
    if (app.performerInvite case final invite?) {
      return _Confirmation(
        key: const ValueKey('performer-invite-confirmation'),
        app: app,
        invite: invite,
      );
    }
    return _Unavailable(
      key: const ValueKey('performer-invite-unavailable'),
      message:
          app.performerInviteError ??
          'This invitation is invalid, expired, or revoked.',
      onRetry: app.performerInviteToken == null
          ? null
          : () => app.openPerformerInvite(app.performerInviteToken!),
    );
  }
}

class _Confirmation extends StatelessWidget {
  const _Confirmation({super.key, required this.app, required this.invite});

  final AppState app;
  final PerformerInviteResolution invite;

  @override
  Widget build(BuildContext context) {
    final adminBandIds = app.performerInviteAdminBandIds;
    final selectedBandId =
        app.performerInviteBandId ?? adminBandIds.firstOrNull;
    final waitingForBands = app.authed && !app.membershipsLoaded;
    final canClaim = !app.authed || selectedBandId != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.queue_music, size: 58, color: context.epColors.accent),
        const SizedBox(height: 18),
        Text(
          'Join ${invite.gigTitle}?',
          textAlign: TextAlign.center,
          style: epDisplay(size: 24),
        ),
        const SizedBox(height: 9),
        Text(
          'You were invited to replace “${invite.performerName}” in the lineup. '
          'Choose which band should appear on the bill.',
          textAlign: TextAlign.center,
          style: epText(
            size: 13,
            color: context.epColors.contentSecondary,
            height: 1.5,
          ),
        ),
        if (waitingForBands) ...[
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator()),
        ] else if (app.authed && adminBandIds.isEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'You need to be an admin of a band before you can claim this spot.',
            textAlign: TextAlign.center,
            style: epText(
              size: 12,
              color: context.epColors.warning,
              height: 1.4,
            ),
          ),
        ] else if (app.authed) ...[
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final bandId in adminBandIds)
                ChoiceChip(
                  label: Text(app.band(bandId)?.name ?? 'Your band'),
                  selected: selectedBandId == bandId,
                  onSelected: app.performerInviteClaiming
                      ? null
                      : (_) => app.selectPerformerInviteBand(bandId),
                ),
            ],
          ),
        ],
        if (app.performerInviteError case final error?) ...[
          const SizedBox(height: 12),
          Text(
            error,
            textAlign: TextAlign.center,
            style: epText(size: 12, color: context.epColors.destructive),
          ),
        ],
        const SizedBox(height: 22),
        EpButton(
          app.performerInviteClaiming
              ? 'CLAIMING…'
              : app.authed
              ? 'CLAIM LINEUP SPOT'
              : 'SIGN IN TO CLAIM',
          kind: app.performerInviteClaiming || waitingForBands || !canClaim
              ? EpButtonKind.disabled
              : EpButtonKind.filled,
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: app.performerInviteClaiming || waitingForBands || !canClaim
              ? null
              : () async {
                  try {
                    await app.confirmPerformerInvite(selectedBandId ?? '');
                  } on Object {
                    // AppState exposes the recoverable error inline.
                  }
                },
        ),
      ],
    );
  }
}

class _Claimed extends StatelessWidget {
  const _Claimed({super.key, required this.invite, required this.onManager});

  final PerformerInviteResolution? invite;
  final VoidCallback onManager;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle, size: 62, color: context.epColors.accent),
        const SizedBox(height: 18),
        Text(
          invite == null
              ? 'Lineup spot claimed.'
              : 'You joined ${invite!.gigTitle}.',
          textAlign: TextAlign.center,
          style: epDisplay(size: 23),
        ),
        const SizedBox(height: 8),
        Text(
          'Your band now appears in the lineup.',
          textAlign: TextAlign.center,
          style: epText(size: 12.5, color: context.epColors.contentSecondary),
        ),
        const SizedBox(height: 22),
        EpButton(
          'OPEN GIG MANAGER',
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: onManager,
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.link_off,
          size: 54,
          color: context.epColors.contentSecondary,
        ),
        const SizedBox(height: 16),
        Text(
          'Invitation unavailable',
          textAlign: TextAlign.center,
          style: epDisplay(size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: epText(
            size: 12.5,
            color: context.epColors.contentSecondary,
            height: 1.45,
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 20),
          EpButton('TRY AGAIN', kind: EpButtonKind.outline, onTap: onRetry),
        ],
      ],
    );
  }
}
