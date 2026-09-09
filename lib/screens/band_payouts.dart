import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

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

  void _showExportSheet() {
    final now = DateTime.now();
    final presets = [
      ('YEAR TO DATE', DateTime(now.year), now),
      (
        'LAST YEAR',
        DateTime(now.year - 1),
        DateTime(now.year).subtract(const Duration(milliseconds: 1)),
      ),
      ('LAST 30 DAYS', now.subtract(const Duration(days: 30)), now),
    ];
    unawaited(
      showEpActionSheet(
        context,
        header: 'Export statement',
        items: [
          for (final (label, from, to) in presets)
            EpActionSheetItem(
              label: label,
              icon: Icons.date_range_outlined,
              onPressed: () => _exportStatement(from, to),
            ),
        ],
      ),
    );
  }

  Future<void> _exportStatement(DateTime from, DateTime to) =>
      _runStripeAction(() async {
        final app = context.read<AppState>();
        final bandId = app.bandId;
        final statement = await app.exportBandPayoutStatementPdf(
          bandId,
          from,
          to,
        );
        if (!mounted || app.bandId != bandId) return;
        final message =
            'Statement downloaded (${statement.payouts.length} payouts)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              statement.truncated
                  ? '$message. Some payouts were left out.'
                  : message,
            ),
          ),
        );
      });

  Widget _buildTicketSales(AppState app) {
    final status = app.bandPayoutStatus;
    if (status == null || !status.hasAccount) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('TICKET SALES', style: textTheme.epLabel),
        const SizedBox(height: 8),
        if (status.canSellTickets)
          const Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: 'TICKET SALES ENABLED',
              tone: EpStatusPillTone.success,
            ),
          )
        else
          EpButton(
            'ENABLE TICKET SALES',
            key: const Key('band-payouts-enable-tickets'),
            onTap: () =>
                _runStripeAction(() => app.enableBandTicketSales(app.bandId)),
          ),
        const SizedBox(height: 8),
        Text(
          'Fans pay you directly through Stripe; EarPlug adds its fee at checkout.',
          style: textTheme.epCaption,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildTaxDetails(AppState app) {
    final status = app.bandPayoutStatus;
    final needsTaxInformation =
        status?.requirementsDue.any(
          RegExp(r'tax|ssn|id_number|verification\.document').hasMatch,
        ) ??
        false;

    return Column(
      key: const Key('stripe-tax-row'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (needsTaxInformation)
              const StatusPill(
                label: 'ACTION NEEDED',
                tone: EpStatusPillTone.warning,
              )
            else
              Icon(
                Icons.check,
                size: 18,
                color: context.epColors.contentSecondary,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'TAX DETAILS',
                style: Theme.of(context).textTheme.epLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (needsTaxInformation) ...[
          Text(
            'Stripe needs your tax information before payouts continue.',
            style: Theme.of(context).textTheme.epBody,
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Stripe collects your tax information (W-9 / 1099) during onboarding. '
          'Update it in your Stripe dashboard.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        if (status?.detailsSubmitted == true) ...[
          const SizedBox(height: 12),
          EpButton(
            'MANAGE IN STRIPE',
            key: const Key('band-payouts-tax-dashboard'),
            kind: EpButtonKind.outline,
            onTap: () => _runStripeAction(app.openBandExpressDashboard),
          ),
        ],
      ],
    );
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
        _buildTicketSales(app),
        _buildTaxDetails(app),
        const SizedBox(height: 12),
        InlineFormFeedback(
          error: _error,
          errorKey: const Key('band-payouts-error'),
        ),
        const SizedBox(height: 12),
        EpButton(
          'EXPORT STATEMENT',
          key: const Key('band-payouts-export'),
          kind: app.bandPayouts.isEmpty
              ? EpButtonKind.disabled
              : EpButtonKind.outline,
          onTap: _showExportSheet,
        ),
        const SizedBox(height: 8),
        Text(
          'Statements are for your records. Stripe issues your tax forms.',
          style: Theme.of(context).textTheme.epCaption,
        ),
        const SectionBar(label: 'PAYOUT HISTORY'),
        const SizedBox(height: 8),
        Column(
          key: const Key('band-payouts-history'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!app.bandPayoutsLoaded)
              const SizedBox.shrink()
            else if (app.bandPayouts.isEmpty)
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
