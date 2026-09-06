import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _stateError(String message) => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    contains(message),
  ),
);

void main() {
  late FakeAuthService auth;
  late DemoRepository repo;

  setUp(() async {
    auth = FakeAuthService();
    await auth.signInDemo();
    repo = DemoRepository(auth: auth);
  });

  test('reserve, pay, and check in paid tickets exactly once', () async {
    final before = DateTime.now();
    final reservation = await repo.reserveTickets(
      gigId: 'g8',
      quantity: 2,
      referralBandSlug: 'foghorn-diet',
    );
    expect(reservation.orderId, startsWith('demo-ticket-order-'));
    expect(reservation.quantity, 2);
    expect(reservation.unitPriceMinor, 2500);
    expect(reservation.unitFeeMinor, 175);
    expect(reservation.subtotalMinor, 5000);
    expect(reservation.feeMinor, 350);
    expect(reservation.totalMinor, 5350);
    expect(reservation.total.label, r'$53.50');
    expect(reservation.currency, 'usd');
    expect(
      reservation.reservedUntil.isBefore(
        before.add(const Duration(minutes: 30)),
      ),
      isFalse,
    );
    expect(
      reservation.reservedUntil.isAfter(
        DateTime.now().add(const Duration(minutes: 30)),
      ),
      isFalse,
    );
    expect(await repo.myTickets(), isEmpty);
    final reservedSales = await repo.ticketSalesForGig('g8');
    expect(reservedSales.reserved, 2);
    expect(reservedSales.available, 38);

    final checkout = await repo.startTicketCheckout(reservation.orderId);
    expect(checkout.sessionId, startsWith('demo-ticket-session-'));
    expect(checkout.url, 'https://demo.stripe/tickets/${reservation.orderId}');
    expect(
      (await repo.ticketOrderStatus(checkout.sessionId))!.status,
      TicketOrderStatus.checkoutOpen,
    );
    await repo.simulateTicketCheckoutCompleted(checkout.sessionId);
    final tickets = await repo.myTickets();
    expect(tickets, hasLength(2));
    expect(tickets.map((ticket) => ticket.id).toSet(), hasLength(2));
    final gig = DemoData.gigs.singleWhere((gig) => gig.id == 'g8');
    for (var index = 0; index < tickets.length; index++) {
      final ticket = tickets[index];
      expect(ticket.orderId, reservation.orderId);
      expect(ticket.gigId, 'g8');
      expect(ticket.status, TicketStatus.valid);
      expect(ticket.checkedInAt, isNull);
      expect(
        ticket.token,
        'earplug:ticket:v2:demo-${reservation.orderId}-${index + 1}',
      );
      expect(ticket.gig.id, gig.id);
      expect(ticket.gig.title, gig.title);
      expect(ticket.gig.slug, gig.slug);
      expect(ticket.gig.startsAt, gig.startsAt);
      expect(ticket.gig.doorsAt, gig.doorsAt);
      expect(ticket.gig.venueName, DemoData.venues[gig.venueId]!.name);
      expect(ticket.gig.lifecycle, GigLifecycle.published);
    }

    // Replaying completion and cancelling a paid order must preserve tickets.
    await repo.simulateTicketCheckoutCompleted(checkout.sessionId);
    await repo.cancelTicketReservation(reservation.orderId);
    await repo.cancelTicketOrder(reservation.orderId);
    expect(
      (await repo.myTickets()).map((ticket) => ticket.id),
      tickets.map((ticket) => ticket.id),
    );
    final state = (await repo.ticketOrderStatus(checkout.sessionId))!;
    expect(state.orderId, reservation.orderId);
    expect(state.gigId, 'g8');
    expect(state.gigSlug, gig.slug);
    expect(state.status, TicketOrderStatus.paid);
    expect(state.quantity, 2);
    expect(state.totalMinor, 5350);
    final sales = await repo.ticketSalesForGig('g8');
    expect(sales.capacity, 40);
    expect(sales.sold, 2);
    expect(sales.reserved, 0);
    expect(sales.available, 38);
    expect(sales.ordersPaid, 1);
    expect(sales.grossMinor, 5000);
    expect(sales.feeMinor, 350);
    expect(sales.netMinor, 5000);

    final wrongEvent = await repo.organizerCheckIn(
      gigId: 'g1',
      payload: tickets.first.token,
    );
    expect(wrongEvent.kind, TicketDoorKind.wrongEvent);
    expect((await repo.ticket(tickets.first.id))!.status, TicketStatus.valid);
    final first = await repo.organizerCheckIn(
      gigId: 'g8',
      payload: tickets.first.token,
    );
    expect(first.kind, TicketDoorKind.checkedIn);
    expect(first.source, 'ticket');
    expect(first.holderName, 'Earplug Fan');
    expect(first.checkedInAt, isNotNull);
    final repeated = await repo.organizerCheckIn(
      gigId: 'g8',
      payload: tickets.first.token,
    );
    expect(repeated.kind, TicketDoorKind.alreadyUsed);
    expect(repeated.source, 'ticket');
    expect(repeated.checkedInAt, first.checkedInAt);
    expect((await repo.ticket(tickets.first.id))!.status, TicketStatus.used);
    final counts = await repo.organizerDoorRoster('g8');
    expect(counts.ticketsSold, 2);
    expect(counts.ticketsCheckedIn, 1);
    expect(counts.rsvpTotal, 0);
    expect(counts.rsvpCheckedIn, 0);
    expect(counts.truncated, isFalse);

    // Use valid batch sizes so this tests capacity, not quantity validation.
    for (var batch = 0; batch < 3; batch++) {
      await repo.reserveTickets(gigId: 'g8', quantity: 10);
    }
    await expectLater(
      repo.reserveTickets(gigId: 'g8', quantity: 9),
      _stateError('Not enough tickets available'),
    );
  });

  test('paid ticket capacity is counted once', () async {
    final oversellRepo = DemoRepository(auth: auth);
    for (final repository in [repo, oversellRepo]) {
      for (var batch = 0; batch < 2; batch++) {
        final reservation = await repository.reserveTickets(
          gigId: 'g8',
          quantity: 10,
        );
        final checkout = await repository.startTicketCheckout(
          reservation.orderId,
        );
        await repository.simulateTicketCheckoutCompleted(checkout.sessionId);
      }
      final tickets = await repository.myTickets();
      expect(tickets, hasLength(20));
      expect(
        tickets.every((ticket) => ticket.status == TicketStatus.valid),
        isTrue,
      );
      expect((await repository.ticketSalesForGig('g8')).available, 20);
    }

    // Each reservation is capped at 10, so reserve the remaining 20 in batches.
    for (var batch = 0; batch < 2; batch++) {
      await repo.reserveTickets(gigId: 'g8', quantity: 10);
    }
    expect((await repo.ticketSalesForGig('g8')).available, 0);

    // Independently attempt 21 more tickets: 10 + 10 fit, but the last does not.
    for (var batch = 0; batch < 2; batch++) {
      await oversellRepo.reserveTickets(gigId: 'g8', quantity: 10);
    }
    await expectLater(
      oversellRepo.reserveTickets(gigId: 'g8', quantity: 1),
      _stateError('Not enough tickets available'),
    );
  });

  test('cancellation releases reserved and checkout-open capacity', () async {
    final reservations = <TicketReservation>[];
    for (var batch = 0; batch < 4; batch++) {
      reservations.add(await repo.reserveTickets(gigId: 'g8', quantity: 10));
    }
    expect((await repo.ticketSalesForGig('g8')).available, 0);
    await expectLater(
      repo.reserveTickets(gigId: 'g8', quantity: 1),
      _stateError('Not enough tickets available'),
    );
    await repo.cancelTicketReservation(reservations.first.orderId);
    await repo.cancelTicketReservation(reservations.first.orderId);
    expect((await repo.ticketSalesForGig('g8')).available, 10);
    await expectLater(
      repo.startTicketCheckout(reservations.first.orderId),
      _stateError('This order can not be checked out'),
    );

    final checkout = await repo.startTicketCheckout(reservations[1].orderId);
    await repo.cancelTicketOrder(reservations[1].orderId);
    await repo.cancelTicketOrder(reservations[1].orderId);
    expect(
      (await repo.ticketOrderStatus(checkout.sessionId))!.status,
      TicketOrderStatus.cancelled,
    );
    final sales = await repo.ticketSalesForGig('g8');
    expect(sales.reserved, 20);
    expect(sales.sold, 0);
    expect(sales.available, 20);
    expect(sales.grossMinor, 0);
    expect(sales.feeMinor, 0);
    expect(sales.netMinor, 0);
    await repo.reserveTickets(gigId: 'g8', quantity: 10);
  });

  test(
    'multiple checkout sessions share one order and one set of tickets',
    () async {
      final reservation = await repo.reserveTickets(gigId: 'g8', quantity: 1);
      final first = await repo.startTicketCheckout(reservation.orderId);
      final reopened = await repo.startTicketCheckout(reservation.orderId);
      await repo.simulateTicketCheckoutCompleted(first.sessionId);
      await repo.simulateTicketCheckoutCompleted(reopened.sessionId);
      expect(await repo.myTickets(), hasLength(1));
      expect(
        (await repo.ticketOrderStatus(first.sessionId))!.status,
        TicketOrderStatus.paid,
      );
      expect(
        (await repo.ticketOrderStatus(reopened.sessionId))!.status,
        TicketOrderStatus.paid,
      );
      expect((await repo.ticketSalesForGig('g8')).ordersPaid, 1);
      await expectLater(
        repo.startTicketCheckout(reservation.orderId),
        _stateError('This order can not be checked out'),
      );
      await auth.signOut();
      expect(await repo.myTickets(), isEmpty);
    },
  );

  test(
    'invalid gigs, quantities, orders, sessions, and tokens are handled',
    () async {
      await expectLater(
        repo.reserveTickets(gigId: 'missing', quantity: 1),
        _stateError('Gig not found'),
      );
      await expectLater(
        repo.reserveTickets(gigId: 'g1', quantity: 1),
        _stateError('This gig does not sell tickets'),
      );
      for (final quantity in [0, -1, 11, 41]) {
        await expectLater(
          repo.reserveTickets(gigId: 'g8', quantity: quantity),
          _stateError('Quantity must be between 1 and 10'),
        );
      }
      await expectLater(
        repo.cancelTicketReservation('missing'),
        _stateError('Order not found'),
      );
      await expectLater(
        repo.cancelTicketOrder('missing'),
        _stateError('Order not found'),
      );
      await expectLater(
        repo.startTicketCheckout('missing'),
        _stateError('Order not found'),
      );
      await expectLater(
        repo.simulateTicketCheckoutCompleted('missing'),
        _stateError('Unknown checkout session'),
      );
      await expectLater(
        repo.ticketSalesForGig('missing'),
        _stateError('Gig not found'),
      );
      expect(await repo.ticket('missing'), isNull);
      expect(await repo.ticketOrderStatus('missing'), isNull);
      for (final payload in ['invalid', 'earplug:ticket:v2:demo-missing-1']) {
        expect(
          (await repo.organizerCheckIn(gigId: 'g8', payload: payload)).kind,
          TicketDoorKind.unknown,
        );
      }
    },
  );

  test(
    'organizer door flow supports RSVP tokens with direct gig IDs',
    () async {
      const payload = 'earplug:ticket:v1:demo-g1';
      expect(
        (await repo.organizerCheckIn(gigId: 'g1', payload: payload)).kind,
        TicketDoorKind.unknown,
      );
      await repo.ensureRsvp('g1');
      final ticket = await repo.ticketForGig('g1');
      expect(ticket.payload, payload);
      expect(
        (await repo.organizerCheckIn(gigId: 'g8', payload: payload)).kind,
        TicketDoorKind.wrongEvent,
      );
      final first = await repo.organizerCheckIn(gigId: 'g1', payload: payload);
      expect(first.kind, TicketDoorKind.checkedIn);
      expect(first.source, 'rsvp');
      expect(first.holderName, 'Earplug Fan');
      expect(first.checkedInAt, isNotNull);
      final repeated = await repo.organizerCheckIn(
        gigId: 'g1',
        payload: payload,
      );
      expect(repeated.kind, TicketDoorKind.alreadyUsed);
      expect(repeated.source, 'rsvp');
      final counts = await repo.organizerDoorRoster('g1');
      expect(counts.rsvpTotal, 1);
      expect(counts.rsvpCheckedIn, 1);
      expect(counts.ticketsSold, 0);
      expect(counts.ticketsCheckedIn, 0);
      expect(counts.truncated, isFalse);
    },
  );

  test('opportunity creation and updates preserve ticket settings', () async {
    final created = await repo.createOpportunity(
      organizationId: 'org1',
      title: 'Paid Showcase',
      venueId: 'v1',
      startsAt: DateTime.now().add(const Duration(days: 30)),
      ticketing: OpportunityTicketing.paid,
      ticketPriceMinor: 2500,
      ticketCapacity: 40,
      ticketCurrency: 'usd',
    );
    var opportunity = (await repo.opportunity(created.opportunityId))!;
    expect(opportunity.ticketPriceMinor, 2500);
    expect(opportunity.ticketCapacity, 40);
    expect(opportunity.ticketCurrency, 'usd');
    final revision = await repo.updateOpportunity(
      opportunityId: created.opportunityId,
      expectedRevision: opportunity.revision,
      ticketPriceMinor: 3000,
      ticketCapacity: 50,
      ticketCurrency: 'eur',
    );
    await repo.updateOpportunity(
      opportunityId: created.opportunityId,
      expectedRevision: revision,
      title: 'Renamed Paid Showcase',
    );
    opportunity = (await repo.opportunity(created.opportunityId))!;
    expect(opportunity.ticketPriceMinor, 3000);
    expect(opportunity.ticketCapacity, 50);
    expect(opportunity.ticketCurrency, 'eur');
  });
}
