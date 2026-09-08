import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';

class OrgTransactionsScreen extends StatefulWidget {
  const OrgTransactionsScreen({super.key});

  @override
  State<OrgTransactionsScreen> createState() => _OrgTransactionsScreenState();
}

class _OrgTransactionsScreenState extends State<OrgTransactionsScreen> {
  final _scrollController = ScrollController();
  String? _loadedOrganizationId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMore);
  }

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
      unawaited(app.loadTransactions(reset: true));
    });
  }

  void _loadMore() {
    if (!_scrollController.hasClients) return;
    final app = context.read<AppState>();
    if (_scrollController.position.extentAfter < 200 &&
        app.canSeeFinance(app.organizationId) &&
        !app.transactionsDone &&
        !app.transactionsLoading) {
      unawaited(app.loadTransactions());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final textTheme = Theme.of(context).textTheme;
    if (!app.canSeeFinance(app.organizationId)) {
      return Padding(
        key: const Key('org-transactions'),
        padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 16),
        child: Text(
          'Finance is for owners and finance members',
          style: textTheme.epBody,
        ),
      );
    }

    return ListView.builder(
      key: const Key('org-transactions'),
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      itemCount: app.transactions.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  BackButton(onPressed: app.back),
                  IconButton(
                    tooltip: 'Refresh transactions',
                    onPressed: () => app.loadTransactions(reset: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Text('TRANSACTIONS', style: textTheme.epPageHeading),
              const SizedBox(height: 16),
            ],
          );
        }
        if (index <= app.transactions.length) {
          final transaction = app.transactions[index - 1];
          return EpCard(
            key: Key('org-tx-${transaction.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: _TransactionRow(transaction: transaction),
          );
        }
        if (app.transactionsLoading) {
          return Padding(
            padding: EdgeInsets.symmetric(
              vertical: app.transactions.isEmpty ? 80 : 16,
            ),
            child: const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (app.transactions.isEmpty) {
          return const EmptyNote(message: 'No transactions yet.');
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final FinanceTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final credit = switch (transaction.kind) {
      LedgerKind.ticketSale ||
      LedgerKind.charge ||
      LedgerKind.disputeRelease => true,
      _ => false,
    };
    final amount = transaction.amount.label.replaceFirst(RegExp(r'^-'), '');
    final tone = switch (transaction.fundsState) {
      FundsState.available || FundsState.paid => EpStatusPillTone.success,
      FundsState.refunded || FundsState.disputed => EpStatusPillTone.warning,
      FundsState.pending ||
      FundsState.reserved ||
      FundsState.unknown => EpStatusPillTone.neutral,
    };
    return LedgerRow(
      title: transaction.label,
      details: [dateLabel(transaction.occurredAt.toLocal())],
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${credit ? '+' : '-'}$amount',
            style: Theme.of(context).textTheme.epMeta.copyWith(
              color: credit ? context.epColors.success : null,
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(
            label: switch (transaction.fundsState) {
              FundsState.pending => 'PENDING',
              FundsState.available => 'AVAILABLE',
              FundsState.reserved => 'RESERVED',
              FundsState.paid => 'PAID',
              FundsState.refunded => 'REFUNDED',
              FundsState.disputed => 'DISPUTED',
              FundsState.unknown => 'UNKNOWN',
            },
            tone: tone,
          ),
        ],
      ),
    );
  }
}
