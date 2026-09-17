import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Shared bodies for the invitation join screens (band and organization).
///
/// Each widget renders one phase of the flow; the screens supply the
/// invitation-specific copy, leading avatar and callbacks.

class JoinLoading extends StatelessWidget {
  const JoinLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('CHECKING INVITATION…', style: Theme.of(context).textTheme.epMeta),
      ],
    );
  }
}

class JoinConfirmation extends StatelessWidget {
  const JoinConfirmation({
    super.key,
    required this.leading,
    required this.title,
    this.titleSize = 24,
    required this.body,
    required this.signedIn,
    required this.accepting,
    required this.confirmLabel,
    this.confirmKey,
    required this.onConfirm,
  });

  final Widget leading;
  final String title;
  final double titleSize;
  final String body;
  final bool signedIn;
  final bool accepting;
  final String confirmLabel;
  final Key? confirmKey;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: leading),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.epDisplayAt(titleSize),
        ),
        const SizedBox(height: 9),
        Text(
          body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.epBody.copyWith(
            fontSize: 13,
            color: context.epColors.contentSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          signedIn
              ? 'You will only join after you confirm below.'
              : 'Sign in first, then return here to confirm. You will not join automatically.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.epCaption.copyWith(
            fontSize: 11,
            color: context.epColors.contentDisabled,
          ),
        ),
        const SizedBox(height: 22),
        EpButton(
          accepting
              ? 'JOINING…'
              : signedIn
              ? confirmLabel
              : 'SIGN IN TO JOIN',
          key: confirmKey,
          kind: accepting ? EpButtonKind.disabled : EpButtonKind.filled,
          onTap: accepting ? null : onConfirm,
        ),
      ],
    );
  }
}

class JoinAccepted extends StatelessWidget {
  const JoinAccepted({
    super.key,
    required this.title,
    required this.buttonLabel,
    required this.onDashboard,
  });

  final String title;
  final String buttonLabel;
  final VoidCallback onDashboard;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle, size: 62, color: context.epColors.accent),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.epDisplayAt(23),
        ),
        const SizedBox(height: 8),
        Text(
          'Your membership is active.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.epCaption.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 22),
        EpButton(buttonLabel, onTap: onDashboard),
      ],
    );
  }
}

class JoinError extends StatelessWidget {
  const JoinError({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

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
          style: Theme.of(context).textTheme.epDisplayAt(22),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.epCaption.copyWith(fontSize: 12.5),
        ),
        if (onAction != null) ...[
          const SizedBox(height: 20),
          EpButton(
            actionLabel ?? 'TRY AGAIN',
            kind: EpButtonKind.outline,
            onTap: onAction,
          ),
        ],
      ],
    );
  }
}
