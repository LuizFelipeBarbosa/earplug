import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_text.dart';
import '../widgets/join_flow.dart';

class BandJoinScreen extends StatelessWidget {
  const BandJoinScreen({super.key});

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
                      'BAND INVITATION',
                      style: Theme.of(context).textTheme.epSectionHeading,
                    ),
                  ),
                ],
              ),
            ),
            const EpHairline(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
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
    if (app.joinInviteLoading) {
      return const JoinLoading(key: ValueKey('join-loading'));
    }
    if (app.joinInviteAccepted) {
      final invite = app.joinInvite;
      return JoinAccepted(
        key: const ValueKey('join-accepted'),
        title: invite == null
            ? 'You joined the band.'
            : 'You joined ${invite.bandName}.',
        buttonLabel: 'OPEN BAND DASHBOARD',
        onDashboard: app.returnToBandDashboard,
      );
    }
    if (app.joinInviteError case final error?) {
      return JoinError(
        key: const ValueKey('join-error'),
        message: error,
        actionLabel: 'TRY AGAIN',
        onAction: app.joinToken == null
            ? null
            : () => app.openJoinInvite(app.joinToken!),
      );
    }
    if (app.joinInvite case final invite?) {
      return JoinConfirmation(
        key: const ValueKey('join-confirmation'),
        leading: Center(child: _InviteAvatar(invite: invite)),
        title: 'Join ${invite.bandName}?',
        titleSize: 24,
        body:
            'You were invited to become a band member. Members can return to the '
            'band dashboard and help manage gigs and media.',
        signedIn: app.authed,
        accepting: app.joinInviteAccepting,
        confirmLabel: 'JOIN BAND',
        onConfirm: () async {
          try {
            await app.confirmJoinInvite();
          } on Object {
            // AppState exposes a recoverable inline error for the screen.
          }
        },
      );
    }
    return const JoinError(
      key: ValueKey('join-empty'),
      message: 'This invitation is invalid, expired, or revoked.',
    );
  }
}

class _InviteAvatar extends StatelessWidget {
  const _InviteAvatar({required this.invite});

  final BandInviteResolution invite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: invite.color,
        borderRadius: BorderRadius.circular(EpLayout.cardRadius),
        border: Border.all(color: context.epColors.outline),
      ),
      child: Text(
        invite.initials,
        style: Theme.of(context).textTheme
            .epDisplayAt(27)
            .copyWith(color: context.epColors.background),
      ),
    );
  }
}
