import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

class BandPayoutsScreen extends StatefulWidget {
  const BandPayoutsScreen({super.key});

  @override
  State<BandPayoutsScreen> createState() => _BandPayoutsScreenState();
}

class _BandPayoutsScreenState extends State<BandPayoutsScreen> {
  String? _loadedBandId;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    final bandId = app.bandId;
    if (_loadedBandId == bandId) return;
    _loadedBandId = bandId;
    _error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || app.bandId != bandId) return;
      unawaited(app.refreshBandPayoutStatus());
      unawaited(app.refreshBandPayouts());
    });
  }

  Future<void> _runStripeAction(Future<void> Function() action) async {
    final app = context.read<AppState>();
    final bandId = app.bandId;
    setState(() => _error = null);
    try {
      await action();
    } catch (error) {
      if (!mounted || app.bandId != bandId) return;
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final status = app.bandPayoutStatus;
    final state = status?.state ?? StripeAccountState.none;
    final enabled = state == StripeAccountState.enabled;
    final needsSetup =
        state == StripeAccountState.onboarding ||
        state == StripeAccountState.restricted;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Text('PAYOUTS', style: Theme.of(context).textTheme.epPageHeading),
        const SizedBox(height: 16),
        EpCard(
          key: const Key('band-payouts-status'),
          variant: EpCardVariant.raised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (enabled)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: 'Payouts enabled',
                    tone: EpStatusPillTone.success,
                  ),
                )
              else
                Text(switch (state) {
                  StripeAccountState.onboarding => 'Finish your Stripe setup',
                  StripeAccountState.restricted =>
                    'Stripe needs more information',
                  _ =>
                    'Set up payouts to receive booking fees. Stripe handles identity and bank details.',
                }, style: Theme.of(context).textTheme.epBody),
              if (state == StripeAccountState.restricted)
                for (final requirement in status!.requirementsDue)
                  Text(
                    requirement,
                    style: Theme.of(context).textTheme.epCaption,
                  ),
              const SizedBox(height: 12),
              if (enabled)
                EpButton(
                  'OPEN STRIPE DASHBOARD',
                  key: const Key('band-payouts-dashboard'),
                  onTap: () => _runStripeAction(app.openBandExpressDashboard),
                )
              else
                EpButton(
                  needsSetup ? 'CONTINUE SETUP' : 'SET UP PAYOUTS',
                  key: const Key('band-payouts-setup'),
                  onTap: () => _runStripeAction(() async {
                    await app.startBandOnboarding();
                    await app.refreshBandPayoutStatus();
                  }),
                ),
              const SizedBox(height: 8),
              EpButton(
                'REFRESH',
                key: const Key('band-payouts-refresh'),
                kind: EpButtonKind.outline,
                onTap: () => _runStripeAction(app.refreshBandPayoutStatus),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InlineFormFeedback(
          error: _error,
          errorKey: const Key('band-payouts-error'),
        ),
        const SizedBox(height: 12),
        const SectionBar(label: 'PAYOUT HISTORY'),
        const SizedBox(height: 8),
        Column(
          key: const Key('band-payouts-history'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (app.bandPayouts.isEmpty)
              const EmptyNote(message: 'No payouts yet.')
            else
              for (final payout in app.bandPayouts) _PayoutRow(payout: payout),
          ],
        ),
      ],
    );
  }
}

class _PayoutRow extends StatelessWidget {
  const _PayoutRow({required this.payout});

  final Payout payout;

  @override
  Widget build(BuildContext context) {
    final kindLabel = payout.kind == PayoutKind.completion
        ? 'Completion payout'
        : 'Forfeited payout';
    final tone = switch (payout.status) {
      PayoutStatus.paid => EpStatusPillTone.success,
      PayoutStatus.held ||
      PayoutStatus.failed ||
      PayoutStatus.reversed => EpStatusPillTone.warning,
      _ => EpStatusPillTone.neutral,
    };

    return Padding(
      key: ValueKey('band-payout-${payout.id}'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel(payout.scheduledFor),
                      style: Theme.of(context).textTheme.epCaption,
                    ),
                    Text(
                      '$kindLabel · ${payout.amount.label}',
                      style: Theme.of(context).textTheme.epBody,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: payout.status.name, tone: tone),
            ],
          ),
          if (payout.holdReason != null) ...[
            const SizedBox(height: 4),
            Text(
              payout.holdReason!,
              style: Theme.of(context).textTheme.epCaption,
            ),
          ],
        ],
      ),
    );
  }
}
