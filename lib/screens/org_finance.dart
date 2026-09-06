import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/sheets.dart';

class OrgFinanceScreen extends StatefulWidget {
  const OrgFinanceScreen({super.key});

  @override
  State<OrgFinanceScreen> createState() => _OrgFinanceScreenState();
}

class _OrgFinanceScreenState extends State<OrgFinanceScreen> {
  String? _loadedOrganizationId;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          app.organizationId != organizationId ||
          !app.canSeeFinance(organizationId)) {
        return;
      }
      unawaited(app.loadFinance());
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
    }
  }

  void _showExportSheet() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final presets = [
      ('LAST 30 DAYS', now.subtract(const Duration(days: 30)), now),
      ('THIS MONTH', monthStart, now),
      (
        'LAST MONTH',
        DateTime(now.year, now.month - 1),
        monthStart.subtract(const Duration(milliseconds: 1)),
      ),
      ('YEAR TO DATE', DateTime(now.year), now),
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
      _runAction(() async {
        final result = await context.read<AppState>().exportStatement(from, to);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Statement downloaded (${result.rows} rows)')),
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
          tabBarClearance,
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
          if (app.financeLoading && overview == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (app.financeError != null && overview == null)
            _LoadError(onRetry: () => app.loadFinance(refresh: true)),
          if (overview != null) ...[
            Column(
              key: const Key('org-finance-funds'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!overview.stripeReady)
                  EpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Connect Stripe to see your balance.',
                          style: textTheme.epBody,
                        ),
                        const SizedBox(height: 12),
                        EpButton(
                          'CONNECT STRIPE',
                          key: const Key('org-finance-connect-stripe'),
                          onTap: () =>
                              _runAction(app.startOrganizationOnboarding),
                        ),
                      ],
                    ),
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
                      child: StatusPill(
                        label: 'stale',
                        tone: EpStatusPillTone.warning,
                      ),
                    ),
                  ],
                ] else
                  const EpCard(
                    child: Text('Balance unavailable. Refresh to try again.'),
                  ),
              ],
            ),
            const SectionBar(label: 'BOOKINGS'),
            _FinanceStats(
              key: const Key('org-finance-bookings'),
              values: [
                ('DUE', overview.dueAmount.label, null),
                ('PAID', overview.paidAmount.label, null),
                ('REFUNDED', overview.refundedAmount.label, null),
                ('DISPUTED', overview.disputedAmount.label, null),
              ],
            ),
            const SectionBar(label: 'PENDING PAYMENTS'),
            Column(
              key: const Key('org-finance-pending'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (overview.pendingPayments.isEmpty)
                  const EmptyNote(message: 'No pending payments.')
                else
                  EpCard(
                    child: Column(
                      children: [
                        for (
                          var i = 0;
                          i < overview.pendingPayments.length;
                          i++
                        ) ...[
                          if (i > 0) const Divider(height: 1),
                          _PendingPaymentRow(
                            payment: overview.pendingPayments[i],
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            const SectionBar(label: 'TICKETS'),
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
            if (overview.stripeReady) ...[
              const SizedBox(height: 10),
              EpButton(
                'MANAGE PAYOUTS IN STRIPE',
                key: const Key('org-finance-stripe'),
                kind: EpButtonKind.light,
                onTap: () => _runAction(app.openOrganizationExpressDashboard),
              ),
            ],
          ],
        ],
      ),
    );
  }
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

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Could not load finance.',
        style: Theme.of(context).textTheme.epBody,
      ),
      const SizedBox(height: 8),
      EpButton('RETRY', kind: EpButtonKind.outline, onTap: onRetry),
    ],
  );
}

String _errorMessage(Object error) =>
    error.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');
