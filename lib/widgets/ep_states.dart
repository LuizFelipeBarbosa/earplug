import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// A failed page load: [message] over an outlined RETRY button. Column
/// alignment and text alignment are the caller's so each screen keeps its
/// current layout.
class EpLoadError extends StatelessWidget {
  const EpLoadError({
    super.key,
    required this.message,
    required this.onRetry,
    this.topPadding = 56,
    this.gap = 12,
    this.textAlign,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String message;
  final VoidCallback onRetry;
  final double topPadding;
  final double gap;
  final TextAlign? textAlign;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            message,
            textAlign: textAlign,
            style: Theme.of(context).textTheme.epBody,
          ),
          SizedBox(height: gap),
          EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
        ],
      ),
    );
  }
}

/// The admin screens' gate for non-admins: a centred [message] with a way
/// back to the fan view (or a custom [action]).
class EpNotAuthorized extends StatelessWidget {
  const EpNotAuthorized({
    super.key,
    required this.message,
    required this.onBack,
    this.action,
  });

  final String message;
  final VoidCallback onBack;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('admin-not-authorized'),
      child: Material(
        color: context.epColors.background,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.epBody,
              ),
              const SizedBox(height: 16),
              action ??
                  EpButton(
                    'BACK TO FAN VIEW',
                    kind: EpButtonKind.outline,
                    onTap: onBack,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A failed section load inside a page: plain [message] with a text RETRY
/// button underneath.
class EpInlineRetry extends StatelessWidget {
  const EpInlineRetry({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryKey,
    this.topGap = 0,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final String message;
  final VoidCallback onRetry;
  final Key? retryKey;
  final double topGap;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        if (topGap > 0) SizedBox(height: topGap),
        Text(message),
        TextButton(
          key: retryKey,
          onPressed: onRetry,
          child: const Text('RETRY'),
        ),
      ],
    );
  }
}

/// A phone-width column of [children] centred on the page background, for
/// return-from-checkout style screens.
class EpCenteredPage extends StatelessWidget {
  const EpCenteredPage({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.epColors.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
