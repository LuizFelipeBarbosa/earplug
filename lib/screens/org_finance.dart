import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_states.dart';
import '../widgets/ep_text.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

class OrgFinanceScreen extends StatefulWidget {
  const OrgFinanceScreen({super.key});

  @override
  State<OrgFinanceScreen> createState() => _OrgFinanceScreenState();
}

class _OrgFinanceScreenState extends State<OrgFinanceScreen> {
  String? _loadedOrganizationId;
  String? _stripeError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppState>();
    final organizationId = app.organizationId;
    if (!app.canSeeFinance(organizationId)) {
      _loadedOrganizationId = null;
      return;
    }
    if (_loadedOrganizationId == organizationId) return;
    _loadedOrganizationId = organizationId;
    _stripeError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          app.organizationId != organizationId ||
          !app.canSeeFinance(organizationId)) {
        return;
      }
      unawaited(app.loadFinance());
      unawaited(app.refreshOrganizationStripeStatus());
    });
  }

  /// Stripe failures stay inline next to the controls rather than in the
  /// finance snackbar, so they read as account state, not a passing notice.
  Future<void> _runStripeAction(Future<void> Function() action) async {
    final app = context.read<AppState>();
    final organizationId = app.organizationId;
    setState(() => _stripeError = null);
    try {
      await action();
    } catch (error) {
      if (!mounted || app.organizationId != organizationId) return;
      setState(() => _stripeError = stripStateErrorPrefix(error));
    }
  }

  Future<void> _continueInStripe(AppState app) => _runStripeAction(() async {
    await app.startOrganizationOnboarding();
    await app.refreshOrganizationStripeStatus();
  });

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(stripStateErrorPrefix(error))));
    }
  }

  void _showExportSheet() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final presets = [
      ('Last 30 days', now.subtract(const Duration(days: 30)), now),
      ('This month', monthStart, now),
      (
        'Last month',
        DateTime(now.year, now.month - 1),
        monthStart.subtract(const Duration(milliseconds: 1)),
      ),
      ('Year to date', DateTime(now.year), now),
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
              onPressed: () => _showExportFormatSheet(from, to),
            ),
        ],
      ),
    );
  }

  Future<void> _showExportFormatSheet(DateTime from, DateTime to) =>
      showEpSheet(
        context,
        (_) => _ExportFormatSheet(
          onCsv: () => _exportStatement(from, to),
          onPdf: () => _exportStatementPdf(from, to),
        ),
      );

  Future<void> _exportStatement(DateTime from, DateTime to) =>
      _runAction(() async {
        final result = await context.read<AppState>().exportStatement(from, to);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Statement downloaded (${result.rows} rows)')),
        );
      });

  Future<void> _exportStatementPdf(
    DateTime from,
    DateTime to,
  ) => _runAction(() async {
    final result = await context.read<AppState>().exportStatementPdf(from, to);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Statement downloaded (${result.transactions.length} transactions)',
        ),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    if (!app.canSeeFinance(app.organizationId)) {
      return Padding(
        key: const Key('org-finance'),
        padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 16),
        child: Text(
          'Finance is for owners and finance members',
          style: textTheme.epBody,
        ),
      );
    }

    final overview = app.financeOverview;
    return RefreshIndicator(
      key: const Key('org-finance'),
      onRefresh: () => app.loadFinance(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          headerTopPad(context),
          16,
          MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BackButton(onPressed: app.back),
              IconButton(
                key: const Key('org-finance-refresh'),
                tooltip: 'Refresh finance',
                onPressed: () => app.loadFinance(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text('FINANCE', style: textTheme.epPageHeading),
          const SizedBox(height: 16),
          _buildStripeSection(app),
          const SizedBox(height: 24),
          if (app.financeLoading && overview == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (app.financeError != null && overview == null)
            EpLoadError(
              message: 'Could not load finance.',
              onRetry: () => app.loadFinance(refresh: true),
              topPadding: 0,
              gap: 8,
              crossAxisAlignment: CrossAxisAlignment.stretch,
            ),
          if (overview != null) ...[
            Column(
              key: const Key('org-finance-funds'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!overview.stripeReady)
                  Text(
                    'Connect Stripe to see your balance.',
                    style: textTheme.epBody,
                  )
                else if (overview.snapshot case final snapshot?) ...[
                  EpStatCard(
                    expand: false,
                    label: 'IN STRIPE',
                    value: snapshot.available.label,
                    caption: 'pending ${snapshot.pending.label}',
                  ),
                  if (snapshot.stale) ...[
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: EpBadge(label: 'stale', tone: EpBadgeTone.warning),
                    ),
                  ],
                ] else
                  const EmptyNote(
                    message: 'Balance unavailable. Refresh to try again.',
                  ),
              ],
            ),
            const EpSectionHeader(label: 'BOOKINGS'),
            _FinanceStats(
              key: const Key('org-finance-bookings'),
              values: [
                ('DUE', overview.dueAmount.label, null),
                ('PAID', overview.paidAmount.label, null),
                ('REFUNDED', overview.refundedAmount.label, null),
                ('DISPUTED', overview.disputedAmount.label, null),
              ],
            ),
            const EpSectionHeader(label: 'PENDING PAYMENTS'),
            Column(
              key: const Key('org-finance-pending'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (overview.pendingPayments.isEmpty)
                  const EmptyNote(message: 'No pending payments.')
                else
                  for (final payment in overview.pendingPayments)
                    _PendingPaymentRow(payment: payment),
              ],
            ),
            const EpSectionHeader(label: 'TICKETS'),
            Column(
              key: const Key('org-finance-tickets'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FinanceStats(
                  values: [
                    ('GROSS', overview.ticketGrossAmount.label, null),
                    (
                      'EARPLUG FEE',
                      overview.ticketFeeAmount.label,
                      'paid by buyers on top of the ticket price',
                    ),
                    ('REFUNDED', overview.ticketRefundedOrgAmount.label, null),
                    ('NET', overview.ticketNetAmount.label, null),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Stripe processing (est.) ${overview.ticketEstimatedProcessingAmount.label}',
                      style: textTheme.epCaption,
                    ),
                    Text(
                      '${overview.tickets.ordersPaid} orders',
                      style: textTheme.epCaption,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            EpButton(
              'TRANSACTIONS',
              key: const Key('org-finance-transactions'),
              onTap: app.openTransactions,
            ),
            const SizedBox(height: 10),
            EpButton(
              'EXPORT STATEMENT',
              key: const Key('org-finance-export'),
              onTap: _showExportSheet,
            ),
          ],
        ],
      ),
    );
  }

  /// The organization's Stripe account: state badge, the one action that
  /// moves it forward, what Stripe still needs, and the tax-details row.
  Widget _buildStripeSection(AppState app) {
    final textTheme = Theme.of(context).textTheme;
    final status = app.organizationStripeStatusFor(app.organizationId);
    final state = status?.state ?? StripeAccountState.unknown;
    final (badgeLabel, badgeTone, sentence) = switch (state) {
      StripeAccountState.enabled => (
        'Connected',
        EpBadgeTone.success,
        'Connected. Payouts go to your Stripe account.',
      ),
      StripeAccountState.onboarding => (
        'Setup in progress — finish in Stripe',
        EpBadgeTone.attention,
        'Setup in progress. Finish onboarding in Stripe to receive payouts.',
      ),
      StripeAccountState.restricted => (
        'Setup in progress — finish in Stripe',
        EpBadgeTone.attention,
        'Stripe needs more information before payouts can continue.',
      ),
      _ => (
        'Set up',
        EpBadgeTone.attention,
        'Not connected. Connect Stripe to sell tickets and receive payouts.',
      ),
    };
    final requirementsDue = status?.requirementsDue ?? const <String>[];
    final needsTaxInformation = requirementsDue.any(
      RegExp(r'tax|ssn|id_number|verification\.document').hasMatch,
    );
    final detailsSubmitted = status?.detailsSubmitted == true;
    final taxCollected = detailsSubmitted && !needsTaxInformation;

    return Column(
      key: const Key('org-finance-stripe-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const EpEyebrow('Stripe'),
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: EpBadge(
                  key: const Key('org-finance-stripe-badge'),
                  label: badgeLabel,
                  tone: badgeTone,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const EpHairline(),
        const SizedBox(height: 12),
        Text(sentence, style: textTheme.epBody),
        if (requirementsDue.isNotEmpty) ...[
          const SizedBox(height: 12),
          const EpEyebrow('Needs information'),
          const SizedBox(height: 4),
          for (final requirement in requirementsDue)
            EpMonoText(requirement, keepCase: true),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (state == StripeAccountState.enabled)
              EpPill(
                key: const Key('org-finance-stripe'),
                label: 'Manage payouts in Stripe',
                variant: EpPillVariant.primary,
                size: EpPillSize.regular,
                onPressed: () =>
                    _runStripeAction(app.openOrganizationExpressDashboard),
              )
            else
              EpPill(
                key: const Key('org-finance-connect-stripe'),
                label: switch (state) {
                  StripeAccountState.onboarding ||
                  StripeAccountState.restricted => 'Continue setup',
                  _ => 'Connect Stripe',
                },
                variant: EpPillVariant.primary,
                size: EpPillSize.regular,
                onPressed: () => _continueInStripe(app),
              ),
            EpPill(
              key: const Key('org-finance-stripe-refresh'),
              label: 'Refresh status',
              variant: EpPillVariant.ghost,
              size: EpPillSize.regular,
              onPressed: () =>
                  _runStripeAction(app.refreshOrganizationStripeStatus),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const EpMonoText('Tax details', size: 12, weight: FontWeight.w500),
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: EpBadge(
                  label: taxCollected
                      ? '✓ Collected via Stripe'
                      : 'Action needed',
                  tone: taxCollected
                      ? EpBadgeTone.success
                      : EpBadgeTone.attention,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Stripe collects tax details (W-9 / 1099) during onboarding and '
          'keeps them in your Stripe dashboard.',
          style: textTheme.epCaption,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          // Until details are submitted the fix is finishing onboarding.
          child: EpPill(
            key: const Key('org-finance-tax-dashboard'),
            label: detailsSubmitted ? 'Manage in Stripe' : 'Add in Stripe',
            onPressed: detailsSubmitted
                ? () => _runStripeAction(app.openOrganizationExpressDashboard)
                : () => _continueInStripe(app),
          ),
        ),
        if (_stripeError != null) ...[
          const SizedBox(height: 8),
          InlineFormFeedback(
            error: _stripeError,
            errorKey: const Key('org-finance-stripe-error'),
          ),
        ],
      ],
    );
  }
}

class _ExportFormatSheet extends StatelessWidget {
  const _ExportFormatSheet({required this.onCsv, required this.onPdf});

  final VoidCallback onCsv;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) => EpSheetShell(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
    mainAxisSize: MainAxisSize.min,
    header: Text(
      'Export format',
      style: Theme.of(context).textTheme.epSectionHeading,
    ),
    children: [
      const SizedBox(height: 16),
      EpButton(
        'CSV',
        key: const Key('org-finance-export-csv'),
        onTap: () {
          Navigator.pop(context);
          onCsv();
        },
      ),
      const SizedBox(height: 10),
      EpButton(
        'PDF',
        key: const Key('org-finance-export-pdf'),
        onTap: () {
          Navigator.pop(context);
          onPdf();
        },
      ),
    ],
  );
}

class _FinanceStats extends StatelessWidget {
  const _FinanceStats({super.key, required this.values});

  final List<(String, String, String?)> values;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final singleColumn =
          constraints.maxWidth < 308 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.35;
      final width = singleColumn
          ? constraints.maxWidth
          : (constraints.maxWidth - 8) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, value, caption) in values)
            SizedBox(
              width: width,
              child: EpStatCard(
                expand: false,
                label: label,
                value: value,
                caption: caption,
              ),
            ),
        ],
      );
    },
  );
}

class _PendingPaymentRow extends StatelessWidget {
  const _PendingPaymentRow({required this.payment});

  final PendingPayment payment;

  @override
  Widget build(BuildContext context) => LedgerRow(
    key: Key('org-finance-pending-${payment.paymentRecordId}'),
    title: payment.label,
    details: [payment.opportunityTitle],
    leading: DateBlock.forDate(
      payment.dueAt.toLocal(),
      semanticLabel: 'Due ${dateLabel(payment.dueAt.toLocal())}',
    ),
    trailing: Text(payment.amount.label),
    onTap: () => context.read<AppState>().openBooking(
      payment.bookingId,
      viewAs: BookingSide.organizer,
    ),
  );
}
