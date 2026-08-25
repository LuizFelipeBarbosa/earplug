import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class BandJoinScreen extends StatelessWidget {
  const BandJoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return ColoredBox(
      color: Ep.background,
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
                    child: Text('BAND INVITATION', style: epDisplay(size: 16)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Ep.border),
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
      return const _JoinLoading(key: ValueKey('join-loading'));
    }
    if (app.joinInviteAccepted) {
      return _JoinAccepted(
        key: const ValueKey('join-accepted'),
        invite: app.joinInvite,
        onDashboard: app.returnToBandDashboard,
      );
    }
    if (app.joinInviteError case final error?) {
      return _JoinError(
        key: const ValueKey('join-error'),
        message: error,
        onRetry: app.joinToken == null
            ? null
            : () => app.openJoinInvite(app.joinToken!),
      );
    }
    if (app.joinInvite case final invite?) {
      return _JoinConfirmation(
        key: const ValueKey('join-confirmation'),
        invite: invite,
        signedIn: app.authed,
        accepting: app.joinInviteAccepting,
        onConfirm: () async {
          try {
            await app.confirmJoinInvite();
          } on Object {
            // AppState exposes a recoverable inline error for the screen.
          }
        },
      );
    }
    return _JoinError(
      key: const ValueKey('join-empty'),
      message: 'This invitation is invalid, expired, or revoked.',
      onRetry: null,
    );
  }
}

class _JoinLoading extends StatelessWidget {
  const _JoinLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'CHECKING INVITATION…',
          style: epText(
            size: 11,
            weight: FontWeight.w900,
            letterSpacing: 1,
            color: Ep.contentSecondary,
          ),
        ),
      ],
    );
  }
}

class _JoinConfirmation extends StatelessWidget {
  const _JoinConfirmation({
    super.key,
    required this.invite,
    required this.signedIn,
    required this.accepting,
    required this.onConfirm,
  });

  final BandInviteResolution invite;
  final bool signedIn;
  final bool accepting;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: _InviteAvatar(invite: invite)),
        const SizedBox(height: 18),
        Text(
          'Join ${invite.bandName}?',
          textAlign: TextAlign.center,
          style: epDisplay(size: 24),
        ),
        const SizedBox(height: 9),
        Text(
          'You were invited to become a band member. Members can return to the '
          'band dashboard and help manage gigs and media.',
          textAlign: TextAlign.center,
          style: epText(size: 13, color: Ep.contentSecondary, height: 1.5),
        ),
        const SizedBox(height: 12),
        Text(
          signedIn
              ? 'You will only join after you confirm below.'
              : 'Sign in first, then return here to confirm. You will not join automatically.',
          textAlign: TextAlign.center,
          style: epText(size: 11, color: Ep.contentDisabled, height: 1.4),
        ),
        const SizedBox(height: 22),
        EpButton(
          accepting
              ? 'JOINING…'
              : signedIn
              ? 'JOIN BAND'
              : 'SIGN IN TO JOIN',
          kind: accepting ? EpButtonKind.disabled : EpButtonKind.filled,
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: accepting ? null : onConfirm,
        ),
      ],
    );
  }
}

class _JoinAccepted extends StatelessWidget {
  const _JoinAccepted({
    super.key,
    required this.invite,
    required this.onDashboard,
  });

  final BandInviteResolution? invite;
  final VoidCallback onDashboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, size: 62, color: Ep.accent),
        const SizedBox(height: 18),
        Text(
          invite == null
              ? 'You joined the band.'
              : 'You joined ${invite!.bandName}.',
          textAlign: TextAlign.center,
          style: epDisplay(size: 23),
        ),
        const SizedBox(height: 8),
        Text(
          'Your membership is active.',
          textAlign: TextAlign.center,
          style: epText(size: 12.5, color: Ep.contentSecondary),
        ),
        const SizedBox(height: 22),
        EpButton(
          'OPEN BAND DASHBOARD',
          padding: const EdgeInsets.symmetric(vertical: 15),
          onTap: onDashboard,
        ),
      ],
    );
  }
}

class _JoinError extends StatelessWidget {
  const _JoinError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.link_off, size: 54, color: Ep.contentSecondary),
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
          style: epText(size: 12.5, color: Ep.contentSecondary, height: 1.45),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 20),
          EpButton('TRY AGAIN', kind: EpButtonKind.outline, onTap: onRetry),
        ],
      ],
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Ep.whiteA(.18)),
      ),
      child: Text(
        invite.initials,
        style: epDisplay(size: 27, color: Ep.background),
      ),
    );
  }
}
