import 'dart:async';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/screens/org_finance.dart';
import 'package:earplug/screens/org_transactions.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  late FakeAuthService auth;
  late _FinanceRepository repository;
  late List<({String filename, String text})> downloads;

  setUp(() async {
    auth = FakeAuthService();
    await auth.signInDemo();
    repository = _FinanceRepository(auth: auth);
    downloads = [];
  });

  Future<AppHarness> pumpScreen(WidgetTester tester, Widget screen) async {
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) {
        app.switchToOrganization('org1');
        app.textFileDownloader = (filename, text) async {
          downloads.add((filename: filename, text: text));
        };
      },
      home: Scaffold(body: screen),
    );
    await enterOrganizer(tester, harness, 'org1');
    return harness;
  }

  testWidgets('finance shows booking and ticket totals with Stripe setup', (
    tester,
  ) async {
    final harness = await pumpScreen(tester, const OrgFinanceScreen());
    final overview = harness.app.financeOverview!;
    expect(find.byKey(const Key('org-finance')), findsOneWidget);
    expect(overview.stripeReady, isFalse);
    expect(overview.snapshot, isNull);
    expect(find.text('Connect Stripe to see your balance.'), findsOneWidget);
    expect(find.byKey(const Key('org-finance-connect-stripe')), findsOneWidget);
    expect(find.text('IN STRIPE'), findsNothing);

    final bookings = find.byKey(const Key('org-finance-bookings'));
    _expectStats(tester, bookings, {
      'DUE': overview.dueAmount.label,
      'PAID': overview.paidAmount.label,
      'REFUNDED': overview.refundedAmount.label,
      'DISPUTED': overview.disputedAmount.label,
    });
    // Seed bookings have no payment records until an offer is accepted.
    expect(overview.pendingPayments, isEmpty);
    expect(find.text('No pending payments.'), findsOneWidget);

    final tickets = find.byKey(const Key('org-finance-tickets'));
    await tester.scrollUntilVisible(tickets, 250);
    _expectStats(tester, tickets, {
      'GROSS': overview.ticketGrossAmount.label,
      'EARPLUG FEE': overview.ticketFeeAmount.label,
      'REFUNDED': overview.ticketRefundedOrgAmount.label,
      'NET': overview.ticketNetAmount.label,
    });
    final feeCard = find.descendant(
      of: tickets,
      matching: find.byWidgetPredicate(
        (widget) => widget is EpStatCard && widget.label == 'EARPLUG FEE',
      ),
    );
    const feeCaption = 'paid by buyers on top of the ticket price';
    expect(tester.widget<EpStatCard>(feeCard).caption, feeCaption);
    expect(
      find.descendant(of: tickets, matching: find.text(feeCaption)),
      findsOneWidget,
    );
    expect(
      find.text(
        'Stripe processing (est.) ${overview.ticketEstimatedProcessingAmount.label}',
      ),
      findsOneWidget,
    );
    expect(find.text('${overview.tickets.ordersPaid} orders'), findsOneWidget);
    final transactions = find.byKey(const Key('org-finance-transactions'));
    await tester.scrollUntilVisible(transactions, 250);
    expect(find.byKey(const Key('org-finance-stripe')), findsNothing);
    await tester.tap(transactions);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.orgTransactions);
  });

  testWidgets('pending payment opens its booking as the organizer', (
    tester,
  ) async {
    await repository.respondToOffer(
      bookingId: 'bk1',
      accept: true,
      expectedRevision: DemoData.bookings['bk1']!.revision,
    );
    final harness = await pumpScreen(tester, const OrgFinanceScreen());
    final payment = harness.app.financeOverview!.pendingPayments.single;
    final row = find.byKey(
      Key('org-finance-pending-${payment.paymentRecordId}'),
    );
    await tester.scrollUntilVisible(row, 250);
    expect(tester.widget<LedgerRow>(row).title, payment.label);
    expect(tester.widget<LedgerRow>(row).details, [payment.opportunityTitle]);
    expect(
      find.descendant(of: row, matching: find.text(payment.amount.label)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(DateBlock)),
      findsOneWidget,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, payment.bookingId);
    expect(repository.bookingSide, BookingSide.organizer);
  });

  for (final preset in [
    'LAST 30 DAYS',
    'THIS MONTH',
    'LAST MONTH',
    'YEAR TO DATE',
  ]) {
    testWidgets('$preset exports the selected date range and downloads CSV', (
      tester,
    ) async {
      await _buyTickets(repository);
      await pumpScreen(tester, const OrgFinanceScreen());
      final export = find.byKey(const Key('org-finance-export'));
      await tester.scrollUntilVisible(export, 250);
      await tester.ensureVisible(export);
      await tester.pumpAndSettle();
      final before = DateTime.now();
      await tester.tap(export);
      await tester.pumpAndSettle();
      final after = DateTime.now();
      expect(
        tester
            .widget<EpActionSheet>(find.byType(EpActionSheet))
            .items
            .map((item) => item.label),
        ['LAST 30 DAYS', 'THIS MONTH', 'LAST MONTH', 'YEAR TO DATE'],
      );
      await tester.tap(find.text(preset));
      await tester.pumpAndSettle();

      final range = repository.statementRange!;
      switch (preset) {
        case 'LAST 30 DAYS':
          expect(range.to.difference(range.from), const Duration(days: 30));
        case 'THIS MONTH':
          expect(range.from, DateTime(range.to.year, range.to.month));
        case 'LAST MONTH':
          expect(range.from, DateTime(before.year, before.month - 1));
          expect(
            range.to,
            DateTime(
              before.year,
              before.month,
            ).subtract(const Duration(milliseconds: 1)),
          );
        case 'YEAR TO DATE':
          expect(range.from, DateTime(range.to.year));
      }
      if (preset != 'LAST MONTH') {
        expect(range.to.isBefore(before), isFalse);
        expect(range.to.isAfter(after), isFalse);
      }
      expect(downloads, hasLength(1));
      expect(downloads.single.filename, startsWith('earplug-statement-'));
      expect(downloads.single.filename, endsWith('.csv'));
      expect(downloads.single.text, repository.statement!.csv);
      expect(
        downloads.single.text,
        startsWith('date,type,label,amount,currency,funds_state,reference'),
      );
      expect(
        find.text('Statement downloaded (${repository.statement!.rows} rows)'),
        findsOneWidget,
      );
    });
  }

  testWidgets('export failures show a readable snackbar', (tester) async {
    final harness = await pumpScreen(tester, const OrgFinanceScreen());
    harness.app.textFileDownloader = (_, _) async =>
        throw StateError('Download failed');
    await tester.scrollUntilVisible(
      find.byKey(const Key('org-finance-export')),
      250,
    );
    await tester.ensureVisible(find.byKey(const Key('org-finance-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('org-finance-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LAST 30 DAYS'));
    await tester.pumpAndSettle();
    expect(find.text('Download failed'), findsOneWidget);
    expect(find.textContaining('Statement downloaded'), findsNothing);
  });

  testWidgets(
    'Stripe balance shows stale status and opens the payout dashboard',
    (tester) async {
      await repository.refreshOrganizationAccountStatus('org1');
      repository.balanceSnapshot = FinanceSnapshot.fromJson({
        'availableMinor': 12500,
        'pendingMinor': 3400,
        'currency': 'usd',
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
        'stale': true,
      });
      final harness = await pumpScreen(tester, const OrgFinanceScreen());
      final snapshot = harness.app.financeOverview!.snapshot!;
      final funds = find.byKey(const Key('org-finance-funds'));
      _expectStats(tester, funds, {'IN STRIPE': snapshot.available.label});
      expect(
        tester
            .widget<EpStatCard>(
              find.descendant(of: funds, matching: find.byType(EpStatCard)),
            )
            .caption,
        'pending ${snapshot.pending.label}',
      );
      expect(
        tester
            .widget<StatusPill>(
              find.descendant(of: funds, matching: find.byType(StatusPill)),
            )
            .tone,
        EpStatusPillTone.warning,
      );
      expect(find.text('STALE'), findsOneWidget);
      expect(find.byKey(const Key('org-finance-connect-stripe')), findsNothing);
      final urls = <String>[];
      harness.app.hostedUrlLauncher = (url) async => urls.add(url);
      final manage = find.byKey(const Key('org-finance-stripe'));
      await tester.scrollUntilVisible(manage, 250);
      await tester.tap(manage);
      await tester.pumpAndSettle();
      expect(urls, ['https://demo.stripe/dashboard/org1']);
    },
  );

  testWidgets(
    'finance refresh shows loading, retries errors, and supports pull to refresh',
    (tester) async {
      final harness = await pumpScreen(tester, const OrgFinanceScreen());
      repository.pendingFinance = Completer<void>();
      repository.failFinance = true;
      harness.app.financeOverview = null;
      await tester.tap(find.byKey(const Key('org-finance-refresh')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.pendingFinance!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not load finance.'), findsOneWidget);
      repository.failFinance = false;
      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('org-finance-bookings')), findsOneWidget);

      final requests = repository.overviewRequests;
      await tester.drag(find.byType(ListView), const Offset(0, 450));
      await tester.pumpAndSettle();
      expect(repository.overviewRequests, requests + 1);
      expect(harness.app.financeError, isNull);
    },
  );

  testWidgets(
    'door members see only the finance access message without loading',
    (tester) async {
      var showFinance = false;
      late StateSetter updateHome;
      final harness = await pumpScreen(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            updateHome = setState;
            return showFinance
                ? const OrgFinanceScreen()
                : const SizedBox.shrink();
          },
        ),
      );
      harness.app.myOrganizations = [
        OrganizationMembership(
          organization: DemoData.organizations['org1']!,
          role: OrganizationRole.door,
        ),
      ];
      harness.app.financeOverview = null;
      final requests = repository.overviewRequests;
      updateHome(() => showFinance = true);
      await tester.pumpAndSettle();
      expect(
        find.text('Finance is for owners and finance members'),
        findsOneWidget,
      );
      expect(find.byType(EpStatCard), findsNothing);
      expect(find.byType(EpButton), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(repository.overviewRequests, requests);
    },
  );

  testWidgets('transactions load and render the complete demo page', (
    tester,
  ) async {
    await _buyTickets(repository);
    await _buyTickets(repository);
    final harness = await pumpScreen(tester, const OrgTransactionsScreen());
    expect(harness.app.transactions, hasLength(2));
    expect(harness.app.transactionsDone, isTrue);
    expect(harness.app.transactionsLoading, isFalse);
    for (final transaction in harness.app.transactions) {
      final row = find.byKey(Key('org-tx-${transaction.id}'));
      expect(row, findsOneWidget);
      expect(
        tester
            .widget<LedgerRow>(
              find.descendant(of: row, matching: find.byType(LedgerRow)),
            )
            .title,
        transaction.label,
      );
      final amount = find.descendant(
        of: row,
        matching: find.text('+${transaction.amount.label}'),
      );
      expect(amount, findsOneWidget);
      expect(
        tester.widget<Text>(amount).style!.color,
        tester.element(row).epColors.success,
      );
      expect(
        tester
            .widget<StatusPill>(
              find.descendant(of: row, matching: find.byType(StatusPill)),
            )
            .tone,
        EpStatusPillTone.success,
      );
    }
    expect(find.text('No transactions yet.'), findsNothing);
  });

  testWidgets('transactions scroll appends the final page without duplicates', (
    tester,
  ) async {
    // Real demo checkouts produce more than the repository's 20-row page cap.
    for (var i = 0; i < 23; i++) {
      await _buyTickets(repository);
    }
    final harness = await pumpScreen(tester, const OrgTransactionsScreen());
    expect(harness.app.transactions, hasLength(20));
    expect(harness.app.transactionsDone, isFalse);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(harness.app.transactions, hasLength(23));
    expect(
      harness.app.transactions.map((transaction) => transaction.id).toSet(),
      hasLength(23),
    );
    expect(harness.app.transactionsDone, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(Key('org-tx-${harness.app.transactions.last.id}')),
      200,
    );
    expect(
      find.byKey(Key('org-tx-${harness.app.transactions.last.id}')),
      findsOneWidget,
    );
  });

  testWidgets('transactions show an empty state before any demo checkouts', (
    tester,
  ) async {
    final harness = await pumpScreen(tester, const OrgTransactionsScreen());
    expect(harness.app.transactions, isEmpty);
    expect(harness.app.transactionsDone, isTrue);
    expect(find.text('No transactions yet.'), findsOneWidget);
  });
}

void _expectStats(
  WidgetTester tester,
  Finder group,
  Map<String, String> expected,
) {
  final stats = tester.widgetList<EpStatCard>(
    find.descendant(of: group, matching: find.byType(EpStatCard)),
  );
  expect({for (final card in stats) card.label: card.value}, expected);
}

Future<void> _buyTickets(DemoRepository repository) async {
  final reservation = await repository.reserveTickets(gigId: 'g8', quantity: 1);
  final checkout = await repository.startTicketCheckout(reservation.orderId);
  await repository.simulateTicketCheckoutCompleted(checkout.sessionId);
}

class _FinanceRepository extends DemoRepository {
  _FinanceRepository({required super.auth});

  int overviewRequests = 0;
  bool failFinance = false;
  Completer<void>? pendingFinance;
  FinanceSnapshot? balanceSnapshot;
  BookingSide? bookingSide;
  ({DateTime from, DateTime to})? statementRange;
  StatementExport? statement;

  @override
  Future<FinanceOverview> financeOverview(String organizationId) async {
    overviewRequests++;
    await pendingFinance?.future;
    if (failFinance) throw StateError('Finance unavailable');
    return super.financeOverview(organizationId);
  }

  @override
  Future<FinanceSnapshot?> refreshFinanceBalance(String organizationId) async =>
      balanceSnapshot ?? await super.refreshFinanceBalance(organizationId);

  @override
  Future<Booking?> booking(String bookingId, {BookingSide? viewAs}) {
    bookingSide = viewAs;
    return super.booking(bookingId, viewAs: viewAs);
  }

  @override
  Future<StatementExport> exportStatement(
    String organizationId, {
    required DateTime from,
    required DateTime to,
  }) async {
    statementRange = (from: from, to: to);
    final result = await super.exportStatement(
      organizationId,
      from: from,
      to: to,
    );
    statement = result;
    return result;
  }
}
