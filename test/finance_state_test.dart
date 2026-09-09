import 'dart:async';
import 'dart:typed_data';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';

void main() {
  late _ControlledFinanceRepository repository;
  late AppState app;
  late List<({String filename, String text})> downloads;
  late List<({String filename, Uint8List bytes, String mimeType})> pdfDownloads;

  setUp(() async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    repository = _ControlledFinanceRepository(auth: auth);
    app = AppState.demo(
      auth: auth,
      repository: repository,
      now: () => DateTime(2020),
    );
    addTearDown(app.dispose);
    app.hostedUrlLauncher = (_) async {};
    downloads = [];
    app.textFileDownloader = (filename, text) async {
      downloads.add((filename: filename, text: text));
    };
    pdfDownloads = [];
    app.bytesFileDownloader = (filename, bytes, mimeType) async {
      pdfDownloads.add((filename: filename, bytes: bytes, mimeType: mimeType));
    };
    await flushAsyncWork();
  });

  test('finance loads await auth readiness and cache the overview', () async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _ControlledFinanceRepository(auth: auth)
      ..pendingAuth = Completer<void>();
    final app = AppState.demo(
      auth: auth,
      repository: repository,
      now: () => DateTime(2020),
    );
    addTearDown(app.dispose);
    app.switchToOrganization('org1');

    // Only the explicit load fetches, after auth is ready.
    final load = app.loadFinance();
    await flushAsyncWork();
    expect(repository.financeOverviewRequests, hasLength(0));
    expect(app.financeLoading, isTrue);
    expect(app.financeOverview, isNull);

    repository.pendingAuth!.complete();
    await load;

    expect(repository.financeOverviewRequests, ['org1']);
    expect(app.financeLoading, isFalse);
    expect(app.financeError, isNull);
    expect(app.financeOverview, isNotNull);
    expect(app.financeOverview, same(repository.lastOverview));
    expect(app.financeOverview!.bookings.activeCount, greaterThan(0));
    expect(app.financeOverview!.currency, 'usd');
    // Demo org1 has no Stripe account until onboarding is completed.
    expect(app.financeOverview!.stripeReady, isFalse);
    expect(app.financeOverview!.snapshot, isNull);
    expect(repository.balanceRequests, isEmpty);

    await app.loadFinance();
    expect(repository.financeOverviewRequests, hasLength(1));
    await app.loadFinance(refresh: true);
    expect(repository.financeOverviewRequests, ['org1', 'org1']);
    expect(app.financeOverview, same(repository.lastOverview));
  });

  test('organization changes clear finance without fetching', () async {
    app.switchToOrganization('org1');
    await flushAsyncWork();
    expect(repository.financeOverviewRequests, isEmpty);

    await app.loadFinance();
    final overview = app.financeOverview;
    expect(overview, isNotNull);
    expect(repository.financeOverviewRequests, ['org1']);

    // Navigation within the same organization preserves its cached overview.
    app.switchToOrganization('org1');
    expect(app.financeOverview, same(overview));

    app.switchToOrganization('org2');
    expect(app.financeOverview, isNull);
    expect(app.financeLoading, isFalse);
    expect(repository.financeOverviewRequests, ['org1']);
    await flushAsyncWork();
    expect(app.financeOverview, isNull);
    expect(repository.financeOverviewRequests, ['org1']);
  });

  test('balance refresh patches only the overview snapshot', () async {
    app.switchToOrganization('org1');
    await app.loadFinance();
    final overview = app.financeOverview!;

    await app.refreshFinanceBalance();

    final refreshed = app.financeOverview!;
    expect(repository.balanceRequests, ['org1']);
    expect(refreshed, isNot(same(overview)));
    expect(refreshed.snapshot, same(repository.balanceSnapshot));
    expect(refreshed.snapshot, isNot(same(overview.snapshot)));
    expect(refreshed.bookings, same(overview.bookings));
    expect(refreshed.tickets, same(overview.tickets));
    expect(refreshed.pendingPayments, same(overview.pendingPayments));
    expect(refreshed.stripeReady, overview.stripeReady);
    expect(refreshed.currency, overview.currency);
  });

  test(
    'balance refresh errors preserve the overview and can be retried',
    () async {
      app.switchToOrganization('org1');
      await app.loadFinance();
      final overview = app.financeOverview!;
      repository.failedBalanceCalls = 1;

      await expectLater(app.refreshFinanceBalance(), completes);

      expect(repository.balanceRequests, ['org1']);
      expect(app.financeOverview, same(overview));
      expect(app.financeError, isNull);

      await app.refreshFinanceBalance();
      expect(repository.balanceRequests, ['org1', 'org1']);
      expect(app.financeOverview!.snapshot, same(repository.balanceSnapshot));
    },
  );

  test(
    'transactions append pages, stop when done, and reset from the start',
    () async {
      app.switchToOrganization('org1');
      final firstPage = repository.transactionPages[null]!;
      final lastPage = repository.transactionPages['next-page']!;

      await app.loadTransactions();

      expect(repository.transactionRequests, [
        (organizationId: 'org1', numItems: 25, cursor: null),
      ]);
      expect(app.transactions, firstPage.items);
      expect(app.transactionsCursor, 'next-page');
      expect(app.transactionsDone, isFalse);
      expect(app.transactionsLoading, isFalse);

      await app.loadTransactions();

      expect(repository.transactionRequests, [
        (organizationId: 'org1', numItems: 25, cursor: null),
        (organizationId: 'org1', numItems: 25, cursor: 'next-page'),
      ]);
      expect(app.transactions, [...firstPage.items, ...lastPage.items]);
      expect(app.transactionsCursor, 'end');
      expect(app.transactionsDone, isTrue);
      await app.loadTransactions();
      expect(repository.transactionRequests, hasLength(2));

      repository.pendingLoads = Completer<void>();
      final reset = app.loadTransactions(reset: true);
      expect(app.transactions, isEmpty);
      expect(app.transactionsCursor, isNull);
      expect(app.transactionsDone, isFalse);
      expect(app.transactionsLoading, isTrue);
      await flushAsyncWork();
      expect(repository.transactionRequests, hasLength(3));
      expect(repository.transactionRequests.last, (
        organizationId: 'org1',
        numItems: 25,
        cursor: null,
      ));

      repository.pendingLoads!.complete();
      await reset;

      expect(app.transactions, firstPage.items);
      expect(app.transactionsCursor, 'next-page');
      expect(app.transactionsDone, isFalse);
      expect(app.transactionsLoading, isFalse);
      await app.loadTransactions();
      expect(app.transactions, [...firstPage.items, ...lastPage.items]);
      expect(app.transactionsDone, isTrue);
      await app.loadTransactions();
      expect(repository.transactionRequests, hasLength(4));
    },
  );

  test(
    'statement export forwards the exact range and downloads the CSV',
    () async {
      app.switchToOrganization('org1');
      final from = DateTime.utc(2026, 2, 3, 4, 5, 6);
      final to = DateTime.utc(2026, 9, 7, 18, 19, 20);

      final statement = await app.exportStatement(from, to);

      expect(repository.statementRequests, [
        (organizationId: 'org1', from: from, to: to),
      ]);
      expect(statement, same(repository.statement));
      expect(downloads, [
        (
          filename: 'earplug-statement-2026-02-03-2026-09-07.csv',
          text: repository.statement.csv,
        ),
      ]);
    },
  );

  test('PDF statement export downloads bytes with a .pdf filename', () async {
    app.switchToOrganization('org1');
    final from = DateTime.utc(2026, 2, 3, 4, 5, 6);
    final to = DateTime.utc(2026, 9, 7, 18, 19, 20);

    final statement = await app.exportStatementPdf(from, to);

    expect(repository.statementRequests, [
      (organizationId: 'org1', from: from, to: to),
    ]);
    expect(statement, same(repository.statement));
    expect(pdfDownloads, hasLength(1));
    final download = pdfDownloads.single;
    expect(download.filename, 'earplug-statement-2026-02-03-2026-09-07.pdf');
    expect(download.mimeType, 'application/pdf');
    expect(download.bytes.take(5), [0x25, 0x50, 0x44, 0x46, 0x2d]);
    expect(downloads, isEmpty);
  });

  test(
    'band payout PDF statement downloads bytes with a .pdf filename',
    () async {
      app.switchToBand('b1');
      final from = DateTime.utc(2026, 2, 3, 4, 5, 6);
      final to = DateTime.utc(2026, 9, 7, 18, 19, 20);

      final statement = await app.exportBandPayoutStatementPdf('b1', from, to);

      expect(repository.payoutStatementRequests, [
        (bandId: 'b1', from: from, to: to),
      ]);
      expect(statement, same(repository.payoutStatement));
      expect(pdfDownloads, hasLength(1));
      final download = pdfDownloads.single;
      expect(download.filename, 'earplug-payouts-b1-2026-02-03-2026-09-07.pdf');
      expect(download.mimeType, 'application/pdf');
      expect(download.bytes.take(5), [0x25, 0x50, 0x44, 0x46, 0x2d]);
      expect(downloads, isEmpty);
    },
  );

  test(
    'applicant insights cache each application until explicitly refreshed',
    () async {
      final first = await app.loadApplicantInsights('app1');
      final second = await app.loadApplicantInsights('app2');

      expect(first, isNotNull);
      expect(first!.band.bandId, 'b1');
      expect(second, isNotNull);
      expect(second!.band.bandId, 'b2');
      expect(app.insightsForApplication('app1'), same(first));
      expect(app.insightsForApplication('app2'), same(second));
      expect(await app.loadApplicantInsights('app1'), same(first));
      expect(await app.loadApplicantInsights('app2'), same(second));
      expect(repository.applicantRequests, ['app1', 'app2']);

      final refreshed = await app.loadApplicantInsights('app1', refresh: true);

      expect(refreshed, isNotNull);
      expect(refreshed, isNot(same(first)));
      expect(app.insightsForApplication('app1'), same(refreshed));
      expect(app.insightsForApplication('app2'), same(second));
      expect(await app.loadApplicantInsights('app1'), same(refreshed));
      expect(repository.applicantRequests, ['app1', 'app2', 'app1']);
    },
  );

  test('band insights cache each band until explicitly refreshed', () async {
    final first = await app.loadMyBandInsights('b1');
    final second = await app.loadMyBandInsights('b2');

    expect(first, isNotNull);
    expect(first!.band.bandId, 'b1');
    expect(second, isNotNull);
    expect(second!.band.bandId, 'b2');
    expect(app.bandInsights('b1'), same(first));
    expect(app.bandInsights('b2'), same(second));
    expect(await app.loadMyBandInsights('b1'), same(first));
    expect(await app.loadMyBandInsights('b2'), same(second));
    expect(repository.bandRequests, ['b1', 'b2']);

    final refreshed = await app.loadMyBandInsights('b1', refresh: true);

    expect(refreshed, isNotNull);
    expect(refreshed, isNot(same(first)));
    expect(app.bandInsights('b1'), same(refreshed));
    expect(app.bandInsights('b2'), same(second));
    expect(await app.loadMyBandInsights('b1'), same(refreshed));
    expect(repository.bandRequests, ['b1', 'b2', 'b1']);
    expect(repository.applicantRequests, isEmpty);
  });

  test('application and band insight caches remain independent', () async {
    final applicant = await app.loadApplicantInsights('app1');
    expect(applicant, isNotNull);
    expect(app.bandInsights('app1'), isNull);
    expect(app.bandInsights('b1'), isNull);
    // Demo artistInsights delegates to myBandInsights inside the repository.
    expect(repository.bandRequests, ['b1']);

    final band = await app.loadMyBandInsights('b1');
    expect(band, isNotNull);
    expect(band, isNot(same(applicant)));
    expect(app.insightsForApplication('b1'), isNull);
    expect(app.insightsForApplication('app1'), same(applicant));
    expect(await app.loadApplicantInsights('app1'), same(applicant));
    expect(await app.loadMyBandInsights('b1'), same(band));
    expect(repository.applicantRequests, ['app1']);
    expect(repository.bandRequests, ['b1', 'b1']);

    final refreshedApplicant = await app.loadApplicantInsights(
      'app1',
      refresh: true,
    );
    expect(refreshedApplicant, isNotNull);
    expect(refreshedApplicant, isNot(same(applicant)));
    expect(app.bandInsights('b1'), same(band));
    expect(await app.loadMyBandInsights('b1'), same(band));
    expect(repository.applicantRequests, ['app1', 'app1']);
    expect(repository.bandRequests, ['b1', 'b1', 'b1']);

    final refreshedBand = await app.loadMyBandInsights('b1', refresh: true);
    expect(refreshedBand, isNotNull);
    expect(refreshedBand, isNot(same(band)));
    expect(app.insightsForApplication('app1'), same(refreshedApplicant));
    expect(await app.loadApplicantInsights('app1'), same(refreshedApplicant));
    expect(repository.applicantRequests, ['app1', 'app1']);
    expect(repository.bandRequests, ['b1', 'b1', 'b1', 'b1']);
  });

  test('sign-out clears finance state and ignores in-flight loads', () async {
    app.switchToOrganization('org1');
    await app.loadFinance();
    await app.loadTransactions();
    await app.loadApplicantInsights('app1');
    await app.loadMyBandInsights('b1');
    expect(app.financeOverview, isNotNull);
    expect(app.transactions, isNotEmpty);
    expect(app.insightsForApplication('app1'), isNotNull);
    expect(app.bandInsights('b1'), isNotNull);

    repository.pendingLoads = Completer<void>();
    final financeLoad = app.loadFinance(refresh: true);
    final balanceRefresh = app.refreshFinanceBalance();
    final transactionsLoad = app.loadTransactions();
    final applicantLoad = app.loadApplicantInsights('app1', refresh: true);
    final bandLoad = app.loadMyBandInsights('b1', refresh: true);
    await flushAsyncWork();
    expect(repository.financeOverviewRequests, ['org1', 'org1']);
    expect(repository.balanceRequests, ['org1']);
    expect(repository.transactionRequests, hasLength(2));
    expect(repository.applicantRequests, ['app1', 'app1']);
    expect(repository.bandRequests, ['b1', 'b1', 'b1', 'b1']);
    expect(app.financeLoading, isTrue);
    expect(app.transactionsLoading, isTrue);

    await app.signOut();

    expect(app.financeOverview, isNull);
    expect(app.transactions, isEmpty);
    expect(app.insightsForApplication('app1'), isNull);
    expect(app.bandInsights('b1'), isNull);

    repository.pendingLoads!.complete();
    await financeLoad;
    await balanceRefresh;
    await transactionsLoad;
    expect(await applicantLoad, isNull);
    expect(await bandLoad, isNull);
    await flushAsyncWork();

    expect(app.financeOverview, isNull);
    expect(app.financeLoading, isFalse);
    expect(app.financeError, isNull);
    expect(app.transactions, isEmpty);
    expect(app.transactionsCursor, isNull);
    expect(app.transactionsDone, isFalse);
    expect(app.transactionsLoading, isFalse);
    expect(app.insightsForApplication('app1'), isNull);
    expect(app.bandInsights('b1'), isNull);
  });
}

class _ControlledFinanceRepository extends DemoRepository {
  _ControlledFinanceRepository({required super.auth});

  final financeOverviewRequests = <String>[];
  final balanceRequests = <String>[];
  final transactionRequests =
      <({String organizationId, int numItems, String? cursor})>[];
  final statementRequests =
      <({String organizationId, DateTime from, DateTime to})>[];
  final payoutStatementRequests =
      <({String bandId, DateTime from, DateTime to})>[];
  final applicantRequests = <String>[];
  final bandRequests = <String>[];
  FinanceOverview? lastOverview;
  int failedBalanceCalls = 0;
  Completer<void>? pendingAuth;
  Completer<void>? pendingLoads;
  final balanceSnapshot = FinanceSnapshot(
    availableMinor: 12500,
    pendingMinor: 3400,
    currency: 'usd',
    fetchedAt: DateTime.utc(2026, 9, 6),
  );
  final transactionPages = <String?, TransactionsPage>{
    null: TransactionsPage(
      items: [
        FinanceTransaction(
          id: 'transaction-1',
          kind: LedgerKind.ticketSale,
          amountMinor: 2500,
          currency: 'usd',
          fundsState: FundsState.available,
          occurredAt: DateTime.utc(2026, 9, 6),
          label: 'Ticket sale',
        ),
        FinanceTransaction(
          id: 'transaction-2',
          kind: LedgerKind.charge,
          amountMinor: 5000,
          currency: 'usd',
          fundsState: FundsState.available,
          occurredAt: DateTime.utc(2026, 9, 5),
          label: 'Deposit',
        ),
      ],
      isDone: false,
      continueCursor: 'next-page',
    ),
    'next-page': TransactionsPage(
      items: [
        FinanceTransaction(
          id: 'transaction-3',
          kind: LedgerKind.charge,
          amountMinor: 10000,
          currency: 'usd',
          fundsState: FundsState.available,
          occurredAt: DateTime.utc(2026, 9, 4),
          label: 'Final payment',
        ),
      ],
      isDone: true,
      continueCursor: 'end',
    ),
  };
  final statement = const StatementExport(
    csv:
        'date,type,label,amount,currency,funds_state,reference\n'
        '2026-09-06T00:00:00.000Z,ticket_sale,"Show, live",25.00,usd,available,order-1',
    rows: 1,
    truncated: false,
  );
  final payoutStatement = PayoutStatement(
    payouts: [
      PayoutStatementRow(
        payoutId: 'payout-1',
        bookingId: 'bk3',
        bookingTitle: 'Summer Closer',
        organizationName: 'The Foghorn Club',
        kind: PayoutKind.completion,
        status: PayoutStatus.paid,
        paidAt: DateTime.utc(2026, 9, 6),
        grossMinor: 10000,
        commissionMinor: 1000,
        netMinor: 9000,
        reversedMinor: 0,
        currency: 'usd',
        stripeTransferId: 'tr-payout-1',
      ),
    ],
    totalNetMinor: 9000,
    truncated: false,
  );

  @override
  Future<void> refreshAuth() => pendingAuth?.future ?? super.refreshAuth();

  @override
  Future<FinanceOverview> financeOverview(String organizationId) async {
    financeOverviewRequests.add(organizationId);
    final overview = await super.financeOverview(organizationId);
    lastOverview = overview;
    await pendingLoads?.future;
    return overview;
  }

  @override
  Future<FinanceSnapshot?> refreshFinanceBalance(String organizationId) async {
    balanceRequests.add(organizationId);
    if (failedBalanceCalls > 0) {
      failedBalanceCalls--;
      throw StateError('refreshFinanceBalance failed');
    }
    await pendingLoads?.future;
    return balanceSnapshot;
  }

  @override
  Future<TransactionsPage> financeTransactions(
    String organizationId, {
    required int numItems,
    String? cursor,
  }) async {
    transactionRequests.add((
      organizationId: organizationId,
      numItems: numItems,
      cursor: cursor,
    ));
    final page = transactionPages[cursor];
    if (page == null) {
      throw StateError('Unexpected transaction cursor: $cursor');
    }
    await pendingLoads?.future;
    return page;
  }

  @override
  Future<StatementExport> exportStatement(
    String organizationId, {
    required DateTime from,
    required DateTime to,
  }) async {
    statementRequests.add((organizationId: organizationId, from: from, to: to));
    return statement;
  }

  @override
  Future<PayoutStatement> bandPayoutStatement(
    String bandId, {
    required DateTime from,
    required DateTime to,
  }) async {
    payoutStatementRequests.add((bandId: bandId, from: from, to: to));
    return payoutStatement;
  }

  @override
  Future<ArtistInsights> artistInsights(String applicationId) async {
    applicantRequests.add(applicationId);
    final insights = await super.artistInsights(applicationId);
    await pendingLoads?.future;
    return insights;
  }

  @override
  Future<ArtistInsights> myBandInsights(String bandId) async {
    bandRequests.add(bandId);
    final insights = await super.myBandInsights(bandId);
    await pendingLoads?.future;
    return insights;
  }
}
