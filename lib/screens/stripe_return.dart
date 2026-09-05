import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

class StripeReturnScreen extends StatefulWidget {
  const StripeReturnScreen({super.key, required this.param});

  final String param;

  @override
  State<StripeReturnScreen> createState() => _StripeReturnScreenState();
}

class _StripeReturnScreenState extends State<StripeReturnScreen> {
  ({bool band, bool refresh, String id})? _link;
  bool _continuing = false;

  @override
  void initState() {
    super.initState();
    final parts = widget.param.split(':');
    if (parts.length != 2 || parts[1].isEmpty) return;
    final kind = parts[0];
    if (!const {'band', 'band-refresh', 'org', 'org-refresh'}.contains(kind)) {
      return;
    }
    final link = (
      band: kind == 'band' || kind == 'band-refresh',
      refresh: kind == 'band-refresh' || kind == 'org-refresh',
      id: parts[1],
    );
    _link = link;
    if (!link.refresh) {
      final app = context.read<AppState>();
      // Switching identity notifies Provider, so wait until this build finishes.
      unawaited(
        Future<void>.microtask(() async {
          if (!mounted) return;
          await app.handleStripeReturn(band: link.band, id: link.id);
        }),
      );
    }
  }

  Future<void> _continueSetup() async {
    final link = _link;
    if (_continuing || link == null) return;
    setState(() => _continuing = true);
    final app = context.read<AppState>();
    try {
      await app.handleStripeReturn(band: link.band, id: link.id);
      // The return handler navigates away; still launch for its active identity.
      if (link.band) {
        await app.startBandOnboarding();
      } else {
        await app.startOrganizationOnboarding();
      }
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final textTheme = Theme.of(context).textTheme;
    final link = _link;
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
                children: [
                  if (link == null) ...[
                    Text(
                      "This link isn't valid.",
                      style: textTheme.epPageHeading,
                    ),
                    const SizedBox(height: 24),
                    EpButton(
                      'BACK',
                      key: const Key('stripe-return-back'),
                      onTap: () => app.resetTo(Screen.home),
                    ),
                  ] else if (link.refresh) ...[
                    Text(
                      'Your Stripe link expired',
                      style: textTheme.epPageHeading,
                    ),
                    const SizedBox(height: 24),
                    EpButton(
                      'CONTINUE SETUP',
                      key: const Key('stripe-return-continue'),
                      kind: _continuing
                          ? EpButtonKind.disabled
                          : EpButtonKind.filled,
                      onTap: _continuing ? null : _continueSetup,
                    ),
                  ] else ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 24),
                    Text(
                      'Checking your Stripe setup…',
                      style: textTheme.epPageHeading,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
