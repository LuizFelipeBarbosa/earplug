import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TicketReservation> _buyTickets(
  DemoRepository repo, {
  int quantity = 1,
}) async {
  final reservation = await repo.reserveTickets(
    gigId: 'g8',
    quantity: quantity,
  );
  final checkout = await repo.startTicketCheckout(reservation.orderId);
  await repo.simulateTicketCheckoutCompleted(checkout.sessionId);
  return reservation;
}

Future<({String bookingId, String opportunityId})> _acceptOffer(
  DemoRepository repo, {
  int grossMinor = 0,
}) async {
  final created = await repo.createOpportunity(
    organizationId: 'org1',
    title: 'Finance "live", showcase',
    venueId: 'v1',
    startsAt: DateTime.now().add(const Duration(days: 30)),
    slots: const [
      SlotInput(role: SlotRole.headliner, guaranteeMinor: 0, required: true),
    ],
  );
  await repo.openOpportunity(
    opportunityId: created.opportunityId,
    expectedRevision: 1,
  );
  final opportunity = (await repo.opportunity(created.opportunityId))!;
  final applicationId = await repo.applyToOpportunity(
    opportunityId: opportunity.id,
    slotId: opportunity.slots.single.id,
    bandId: 'b1',
    message: 'Ready to play.',
  );
  await repo.reviewApplication(
    applicationId: applicationId,
    action: ArtistApplicationReviewAction.shortlisted,
  );
  final offer = await repo.sendOffer(
    applicationId: applicationId,
    grossMinor: grossMinor,
    cancellationTemplate: CancellationTemplate.standard,
  );
  await repo.respondToOffer(
    bookingId: offer.bookingId,
    accept: true,
    expectedRevision: offer.revision,
  );
  return (bookingId: offer.bookingId, opportunityId: opportunity.id);
}

void main() {
  late FakeAuthService auth;
  late DemoRepository repo;

  setUp(() async {
    auth = FakeAuthService();
    await auth.signInDemo();
    repo = DemoRepository(auth: auth);
  });

  test(
    'finance totals track paid tickets for their organization only',
    () async {
      final before = await repo.financeOverview('org1');
      final reservation = await repo.reserveTickets(gigId: 'g8', quantity: 2);
      expect(
        (await repo.financeOverview('org1')).tickets.ordersPaid,
        before.tickets.ordersPaid,
      );
      final checkout = await repo.startTicketCheckout(reservation.orderId);
      expect(
        (await repo.financeOverview('org1')).tickets.grossMinor,
        before.tickets.grossMinor,
      );
      await repo.simulateTicketCheckoutCompleted(checkout.sessionId);
      final after = await repo.financeOverview('org1');
      expect(after.tickets.ordersPaid, before.tickets.ordersPaid + 1);
      expect(after.tickets.grossMinor, before.tickets.grossMinor + 5000);
      expect(after.tickets.feeMinor, before.tickets.feeMinor + 350);
      expect(after.tickets.netMinor, before.tickets.netMinor + 5000);
      expect(after.tickets.truncated, isFalse);
      expect(after.currency, 'usd');
      expect((await repo.financeOverview('another-org')).tickets.ordersPaid, 0);
      await repo.simulateTicketCheckoutCompleted(checkout.sessionId);
      expect(
        (await repo.financeOverview('org1')).tickets.ordersPaid,
        after.tickets.ordersPaid,
      );
    },
  );

  test(
    'finance balances use the same Stripe readiness and derived totals',
    () async {
      expect((await repo.financeOverview('org1')).stripeReady, isFalse);
      expect((await repo.financeOverview('org1')).snapshot, isNull);
      expect(await repo.refreshFinanceBalance('org1'), isNull);
      await repo.startOrganizationOnboarding('org1');
      expect(await repo.refreshFinanceBalance('org1'), isNull);
      await repo.refreshOrganizationAccountStatus('org1');
      final before = (await repo.refreshFinanceBalance('org1'))!;
      await _buyTickets(repo, quantity: 2);
      final overview = await repo.financeOverview('org1');
      final refreshed = (await repo.refreshFinanceBalance('org1'))!;
      expect(overview.stripeReady, isTrue);
      expect(refreshed.availableMinor, before.availableMinor + 5000);
      expect(refreshed.available, overview.snapshot!.available);
      expect(refreshed.pending, overview.snapshot!.pending);
      expect(refreshed.fetchedAt, overview.snapshot!.fetchedAt);
    },
  );

  test('booking payments move from pending totals to the ledger', () async {
    repo.demoPaymentsEnabled = true;
    final before = await repo.financeOverview('org1');
    final accepted = await _acceptOffer(repo, grossMinor: 10000);
    final pending = await repo.financeOverview('org1');
    expect(pending.bookings.dueMinor, before.bookings.dueMinor + 10000);
    expect(pending.bookings.activeCount, before.bookings.activeCount + 1);
    final payment = pending.pendingPayments.single;
    expect(payment.bookingId, accepted.bookingId);
    expect(payment.opportunityTitle, 'Finance "live", showcase');
    expect(payment.amount.currency, pending.currency);
    final checkout = await repo.startInstallmentCheckout(
      payment.paymentRecordId,
    );
    await repo.simulateCheckoutCompleted(checkout.sessionId);
    final paid = await repo.financeOverview('org1');
    expect(paid.bookings.dueMinor, before.bookings.dueMinor);
    expect(paid.bookings.paidMinor, before.bookings.paidMinor + 10000);
    expect(paid.pendingPayments, isEmpty);
    final transaction = (await repo.financeTransactions(
      'org1',
      numItems: 20,
    )).items.single;
    expect(transaction.kind, LedgerKind.charge);
    expect(transaction.id, payment.paymentRecordId);
    expect(transaction.bookingId, accepted.bookingId);
    expect(transaction.amountMinor, 10000);
  });

  test(
    'finance pagination reaches all transactions and caps pages at twenty',
    () async {
      final orderIds = <String>{};
      for (var index = 0; index < 23; index++) {
        orderIds.add((await _buyTickets(repo)).orderId);
      }
      final large = await repo.financeTransactions('org1', numItems: 100);
      expect(large.items, hasLength(20));
      expect(large.isDone, isFalse);
      expect(large.continueCursor, '20');
      final found = <FinanceTransaction>[];
      String? cursor;
      for (var pageNumber = 0; pageNumber < 8; pageNumber++) {
        final page = await repo.financeTransactions(
          'org1',
          numItems: 3,
          cursor: cursor,
        );
        found.addAll(page.items);
        expect(page.items.length, lessThanOrEqualTo(3));
        expect(page.isDone, pageNumber == 7);
        expect(page.continueCursor, found.length.toString());
        cursor = page.continueCursor;
      }
      expect(found, hasLength(23));
      expect(
        found.map((transaction) => transaction.ticketOrderId).toSet(),
        orderIds,
      );
      for (var index = 1; index < found.length; index++) {
        expect(
          found[index].occurredAt.isAfter(found[index - 1].occurredAt),
          isFalse,
        );
      }
      final exhausted = await repo.financeTransactions(
        'org1',
        numItems: 3,
        cursor: cursor,
      );
      expect(exhausted.items, isEmpty);
      expect(exhausted.isDone, isTrue);
      final otherOrg = await repo.financeTransactions(
        'another-org',
        numItems: 3,
      );
      expect(otherOrg.items, isEmpty);
      expect(otherOrg.isDone, isTrue);
    },
  );

  test('statement CSV includes all rows and uses inclusive date bounds', () async {
    final first = await _buyTickets(repo);
    final second = await _buyTickets(repo, quantity: 2);
    final ledger = (await repo.financeTransactions('org1', numItems: 20)).items;
    final statement = await repo.exportStatement(
      'org1',
      from: ledger.last.occurredAt,
      to: ledger.first.occurredAt,
    );
    final lines = statement.csv.split('\n');
    expect(
      lines.first,
      'date,type,label,amount,currency,funds_state,reference',
    );
    expect(statement.rows, 2);
    expect(lines.length - 1, statement.rows);
    expect(
      statement.csv,
      contains(
        ',ticketSale,Paid Show at the Vault,25.00,usd,available,${first.orderId}',
      ),
    );
    expect(
      statement.csv,
      contains(
        ',ticketSale,Paid Show at the Vault,50.00,usd,available,${second.orderId}',
      ),
    );
    expect(statement.truncated, isFalse);
    final empty = await repo.exportStatement(
      'org1',
      from: ledger.first.occurredAt.add(const Duration(days: 1)),
      to: ledger.first.occurredAt.add(const Duration(days: 2)),
    );
    expect(empty.rows, 0);
    expect(empty.csv, lines.first);
  });

  test(
    'insights suppress samples below five events and reflect interactions',
    () async {
      final before = await repo.myBandInsights('b1');
      expect(before.window.events, lessThan(5));
      expect(
        before.window.events,
        DemoData.gigs.where((gig) => gig.lineup.contains('b1')).length,
      );
      expect(before.estimatedDraw, isNull);
      expect(before.returningSuppressed, isTrue);
      expect(before.returningAttendees, 0);
      expect(before.attribution.suppressed, isTrue);
      expect([
        before.attribution.referral,
        before.attribution.follow,
        before.attribution.unattributed,
      ], everyElement(0));
      for (final partition in [
        before.byArea,
        before.byVenueType,
        before.byWeekday,
        before.byPriceBand,
      ]) {
        expect(partition.suppressed, isTrue);
        expect(partition.buckets, isEmpty);
      }
      final applicant = await repo.artistInsights('app1');
      expect(applicant.band.bandId, 'b1');
      expect(applicant.rsvpTotal, before.rsvpTotal);
      await repo.ensureFollow('b1');
      await repo.ensureRsvp('g2');
      await _buyTickets(repo, quantity: 2);
      final ticket = (await repo.myTickets()).first;
      await repo.organizerCheckIn(gigId: 'g8', payload: ticket.token);
      final after = await repo.myBandInsights('b1');
      expect(after.followers, before.followers + 1);
      expect(after.rsvpTotal, before.rsvpTotal + 1);
      expect(after.ticketsSold, before.ticketsSold + 2);
      expect(after.checkIns, before.checkIns + 1);
      expect(after.estimatedDraw, isNull);
      expect(after.byArea.suppressed, isTrue);
    },
  );

  test('estimated draw becomes available at five qualifying events', () async {
    expect((await repo.myBandInsights('b1')).window.events, 3);
    await _acceptOffer(repo);
    await _acceptOffer(repo);
    final insights = await repo.myBandInsights('b1');
    expect(insights.window.events, 5);
    expect(insights.estimatedDraw, isNotNull);
    expect(insights.estimatedDraw!.events, 5);
    expect(insights.estimatedDraw!.basis, DrawBasis.rsvps);
    expect(
      insights.estimatedDraw!.high,
      greaterThanOrEqualTo(insights.estimatedDraw!.low),
    );
    expect(insights.returningSuppressed, isFalse);
    expect(insights.attribution.suppressed, isFalse);
    expect(
      insights.attribution.referral +
          insights.attribution.follow +
          insights.attribution.unattributed,
      insights.rsvpTotal + insights.ticketsSold,
    );
  });

  test(
    'ticketing updates increment revisions, reject stale writes, and update gigs',
    () async {
      final accepted = await _acceptOffer(repo);
      final existing = (await repo.opportunity(accepted.opportunityId))!;
      final revision = await repo.updateOpportunityTicketing(
        opportunityId: existing.id,
        expectedRevision: existing.revision,
        ticketPriceMinor: 3000,
        ticketCapacity: 50,
      );
      expect(revision, existing.revision + 1);
      final updated = (await repo.opportunity(existing.id))!;
      expect(updated.revision, revision);
      expect(updated.ticketPriceMinor, 3000);
      expect(updated.ticketCapacity, 50);
      expect(updated.title, existing.title);
      final gig = (await repo.feed().first).gigs.singleWhere(
        (gig) => gig.opportunityId == existing.id,
      );
      expect(gig.ticketPriceMinor, 3000);
      expect(gig.numericCapacity, 50);
      await expectLater(
        repo.updateOpportunityTicketing(
          opportunityId: existing.id,
          expectedRevision: existing.revision,
          ticketPriceMinor: 4000,
          ticketCapacity: 60,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Opportunity changed elsewhere',
          ),
        ),
      );
      expect((await repo.opportunity(existing.id))!.ticketPriceMinor, 3000);
      expect(
        (await repo.feed().first).gigs
            .singleWhere((candidate) => candidate.id == gig.id)
            .numericCapacity,
        50,
      );
    },
  );
}
