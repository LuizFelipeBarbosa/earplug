import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/async.dart';

void main() {
  late _ControlledTicketRepository repository;
  late AppState app;
  late List<String> launched;

  setUp(() async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    repository = _ControlledTicketRepository(auth: auth);
    app = AppState.demo(
      auth: auth,
      repository: repository,
      now: () => DateTime(2020),
    );
    addTearDown(app.dispose);
    launched = [];
    app.hostedUrlLauncher = (url) async {
      launched.add(url);
    };
    await flushAsyncWork();
  });

  test(
    'wallet loads await auth readiness and populate the ticket cache',
    () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _ControlledTicketRepository(auth: auth)
        ..pendingAuth = Completer<void>();
      final reservation = await repository.reserveTickets(
        gigId: 'g8',
        quantity: 2,
      );
      final checkout = await repository.startTicketCheckout(
        reservation.orderId,
      );
      await repository.simulateTicketCheckoutCompleted(checkout.sessionId);
      final app = AppState.demo(
        auth: auth,
        repository: repository,
        now: () => DateTime(2020),
      );
      addTearDown(app.dispose);

      final load = app.loadMyTickets();
      await flushAsyncWork();
      expect(repository.myTicketsCalls, 0);
      expect(app.myTicketsLoaded, isFalse);

      repository.pendingAuth!.complete();
      await load;

      expect(repository.myTicketsCalls, 1);
      expect(app.myTicketsLoaded, isTrue);
      expect(app.myTickets, hasLength(2));
      for (final ticket in app.myTickets) {
        expect(app.ticketById(ticket.id), same(ticket));
        expect(ticket.orderId, reservation.orderId);
      }
      await app.loadMyTickets();
      expect(repository.myTicketsCalls, 1);
      await app.loadMyTickets(refresh: true);
      expect(repository.myTicketsCalls, 2);
    },
  );

  test('failed wallet loads can be retried', () async {
    repository.failLoads = true;
    await app.loadMyTickets();
    expect(app.myTicketsLoaded, isFalse);

    repository.failLoads = false;
    await app.loadMyTickets();
    expect(app.myTicketsLoaded, isTrue);
    expect(repository.myTicketsCalls, 2);
  });

  test(
    'reserveTickets stores the reservation and forwards its arguments',
    () async {
      final reservation = await app.reserveTickets('g8', 2);

      expect(app.pendingReservation, same(reservation));
      expect(reservation.quantity, 2);
      expect(repository.reservationRequest, (
        gigId: 'g8',
        quantity: 2,
        referralBandSlug: null,
      ));
      await expectLater(app.reserveTickets('g8', 0), throwsStateError);
      expect(app.pendingReservation, same(reservation));
    },
  );

  test(
    'startTicketCheckout launches Checkout and returns its session id',
    () async {
      final reservation = await app.reserveTickets('g8', 1);

      final sessionId = await app.startTicketCheckout(reservation.orderId);

      expect(launched, ['https://demo.stripe/tickets/${reservation.orderId}']);
      expect(sessionId, startsWith('demo-ticket-session-'));
      final status = await repository.ticketOrderStatus(sessionId);
      expect(status?.orderId, reservation.orderId);
      expect(status?.status, TicketOrderStatus.checkoutOpen);
    },
  );

  test(
    'Checkout polls until paid, clears the reservation, and refreshes tickets',
    () async {
      final reservation = await app.reserveTickets('g8', 2);
      final sessionId = await app.startTicketCheckout(reservation.orderId);
      await app.loadMyTickets();
      final poll = app.awaitTicketCheckout(
        sessionId,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 200),
      );
      await flushAsyncWork();
      expect(repository.checkoutStatusRequests, isNotEmpty);
      expect(app.pendingReservation, same(reservation));

      await repository.simulateTicketCheckoutCompleted(sessionId);
      final status = await poll;
      await flushAsyncWork();

      expect(status?.status, TicketOrderStatus.paid);
      expect(repository.checkoutStatusRequests.length, greaterThanOrEqualTo(2));
      expect(app.pendingReservation, isNull);
      expect(repository.myTicketsCalls, 2);
      expect(app.myTickets, hasLength(2));
    },
  );

  for (final terminal in [
    TicketOrderStatus.expired,
    TicketOrderStatus.cancelled,
    TicketOrderStatus.refunded,
  ]) {
    test(
      'Checkout resolves on ${terminal.name} and refreshes the wallet',
      () async {
        final reservation = await app.reserveTickets('g8', 1);
        repository.checkoutResult = TicketOrderState(
          orderId: reservation.orderId,
          gigId: 'g8',
          status: terminal,
          quantity: reservation.quantity,
          totalMinor: reservation.totalMinor,
          currency: reservation.currency,
        );

        final status = await app.awaitTicketCheckout(
          'cs_terminal',
          interval: const Duration(milliseconds: 5),
          timeout: const Duration(milliseconds: 200),
        );
        await flushAsyncWork();

        expect(status?.status, terminal);
        expect(app.pendingReservation, isNull);
        expect(repository.checkoutStatusRequests, ['cs_terminal']);
        expect(repository.myTicketsCalls, 1);
        expect(app.myTicketsLoaded, isTrue);
      },
    );
  }

  test('Checkout retries poll errors', () async {
    final reservation = await app.reserveTickets('g8', 1);
    final sessionId = await app.startTicketCheckout(reservation.orderId);
    await repository.simulateTicketCheckoutCompleted(sessionId);
    repository.failedCheckoutCalls = 1;

    final status = await app.awaitTicketCheckout(
      sessionId,
      interval: const Duration(milliseconds: 5),
      timeout: const Duration(milliseconds: 200),
    );
    await flushAsyncWork();

    expect(status?.status, TicketOrderStatus.paid);
    expect(repository.checkoutStatusRequests, [sessionId, sessionId]);
  });

  test(
    'nonterminal Checkout times out without clearing or refreshing',
    () async {
      final reservation = await app.reserveTickets('g8', 1);
      final sessionId = await app.startTicketCheckout(reservation.orderId);

      final status = await app.awaitTicketCheckout(
        sessionId,
        interval: const Duration(milliseconds: 5),
        timeout: const Duration(milliseconds: 25),
      );

      expect(status, isNull);
      expect(repository.checkoutStatusRequests, isNotEmpty);
      expect(repository.myTicketsCalls, 0);
      expect(app.pendingReservation, same(reservation));
    },
  );

  test(
    'releaseReservation clears state before cancelling the captured order',
    () async {
      final reservation = await app.reserveTickets('g8', 1);
      repository.pendingCancellation = Completer<void>();
      final release = app.releaseReservation();

      expect(app.pendingReservation, isNull);
      expect(repository.cancellationRequests, [reservation.orderId]);
      repository.pendingCancellation!.complete();
      await release;
      await app.releaseReservation();
      expect(repository.cancellationRequests, [reservation.orderId]);
      expect((await repository.ticketSalesForGig('g8')).reserved, 0);
    },
  );

  for (final message in ['ALREADY cancelled', 'Network unavailable']) {
    test(
      'releaseReservation stays cleared when cancellation says $message',
      () async {
        final reservation = await app.reserveTickets('g8', 1);
        repository.cancellationError = StateError(message);

        await app.releaseReservation();

        expect(app.pendingReservation, isNull);
        expect(repository.cancellationRequests, [reservation.orderId]);
      },
    );
  }

  test(
    'URL referrals are trimmed, forwarded by default, and can be overridden',
    () async {
      final app = AppState.demo(
        auth: repository.auth,
        repository: repository,
        initialReferralBandSlug: ' some-band ',
        now: () => DateTime(2020),
      );
      addTearDown(app.dispose);
      await flushAsyncWork();

      await app.reserveTickets('g8', 1);
      expect(repository.reservationRequest?.referralBandSlug, 'some-band');
      await app.reserveTickets('g8', 1, referralBandSlug: 'explicit-band');
      expect(repository.reservationRequest?.referralBandSlug, 'explicit-band');
      await app.signOut();
      expect(app.ticketReferralBandSlug, 'some-band');
    },
  );

  test(
    'loadTicket uses its cache and refreshes matching wallet entries',
    () async {
      final reservation = await app.reserveTickets('g8', 2);
      final sessionId = await app.startTicketCheckout(reservation.orderId);
      await repository.simulateTicketCheckoutCompleted(sessionId);
      await app.loadMyTickets();
      final ticket = app.myTickets.first;
      final otherTicket = app.myTickets.last;

      expect(await app.loadTicket(ticket.id), same(ticket));
      expect(repository.ticketRequests, isEmpty);
      await app.organizerCheckIn('g8', ticket.token);
      final refreshed = await app.loadTicket(ticket.id, refresh: true);

      expect(repository.ticketRequests, [ticket.id]);
      expect(refreshed?.status, TicketStatus.used);
      expect(app.ticketById(ticket.id), same(refreshed));
      expect(app.myTickets, [refreshed, otherTicket]);
      repository.failLoads = true;
      expect(await app.loadTicket(ticket.id, refresh: true), same(refreshed));
      expect(app.myTickets, [refreshed, otherTicket]);
    },
  );

  test('loading a ticket by id does not append it to the wallet', () async {
    final reservation = await app.reserveTickets('g8', 1);
    final sessionId = await app.startTicketCheckout(reservation.orderId);
    await repository.simulateTicketCheckoutCompleted(sessionId);
    final ticket = (await repository.myTickets()).single;

    expect(await app.loadTicket(ticket.id), same(ticket));
    expect(app.ticketById(ticket.id), same(ticket));
    expect(app.myTickets, isEmpty);
    expect(app.myTicketsLoaded, isFalse);
    expect(await app.loadTicket('missing'), isNull);
  });

  test('sales are cached, refreshed, and preserved after errors', () async {
    final initial = await app.loadTicketSales('g8');
    await app.reserveTickets('g8', 2);
    expect(await app.loadTicketSales('g8'), same(initial));
    expect(repository.salesRequests, ['g8']);

    final refreshed = await app.loadTicketSales('g8', refresh: true);
    expect(refreshed?.reserved, 2);
    expect(app.salesFor('g8'), same(refreshed));
    repository.failLoads = true;
    expect(await app.loadTicketSales('g8', refresh: true), same(refreshed));
  });

  test('organizer door actions forward the gig and ticket payload', () async {
    final reservation = await app.reserveTickets('g8', 1);
    final sessionId = await app.startTicketCheckout(reservation.orderId);
    await repository.simulateTicketCheckoutCompleted(sessionId);
    final ticket = (await repository.myTickets()).single;

    final result = await app.organizerCheckIn('g8', ticket.token);
    final counts = await app.organizerDoorRoster('g8');

    expect(result.kind, TicketDoorKind.checkedIn);
    expect(counts.ticketsSold, 1);
    expect(counts.ticketsCheckedIn, 1);
  });

  test(
    'sign-out clears ticket state and ignores late loads and polls',
    () async {
      final reservation = await app.reserveTickets('g8', 1);
      final sessionId = await app.startTicketCheckout(reservation.orderId);
      await repository.simulateTicketCheckoutCompleted(sessionId);
      await app.loadMyTickets();
      await app.loadTicketSales('g8');
      final ticket = app.myTickets.single;
      final paid = await repository.ticketOrderStatus(sessionId);
      repository.pendingLoads = Completer<void>();
      repository.pendingCheckout = Completer<TicketOrderState?>();
      final walletLoad = app.loadMyTickets(refresh: true);
      final ticketLoad = app.loadTicket(ticket.id, refresh: true);
      final salesLoad = app.loadTicketSales('g8', refresh: true);
      final reservationLoad = app.reserveTickets('g8', 1);
      final poll = app.awaitTicketCheckout(sessionId);
      await flushAsyncWork();

      await app.signOut();
      repository.pendingLoads!.complete();
      repository.pendingCheckout!.complete(paid);
      await walletLoad;
      expect(await ticketLoad, isNull);
      await salesLoad;
      await reservationLoad;
      expect(await poll, isNull);
      await flushAsyncWork();

      expect(app.myTickets, isEmpty);
      expect(app.myTicketsLoaded, isFalse);
      expect(app.ticketById(ticket.id), isNull);
      expect(app.pendingReservation, isNull);
      expect(app.salesFor('g8'), isNull);
      expect(repository.myTicketsCalls, 2);
    },
  );

  test('disposing during a Checkout poll prevents further work', () async {
    final disposedApp = AppState.demo(repository: repository);
    await flushAsyncWork();
    repository.pendingCheckout = Completer<TicketOrderState?>();
    final poll = disposedApp.awaitTicketCheckout('cs_pending');
    disposedApp.dispose();
    repository.pendingCheckout!.complete(null);

    expect(await poll, isNull);
    await flushAsyncWork();
    expect(repository.checkoutStatusRequests, ['cs_pending']);
    expect(repository.myTicketsCalls, 0);
    await disposedApp.loadMyTickets();
    expect(await disposedApp.loadTicket('missing'), isNull);
    expect(repository.myTicketsCalls, 0);
    expect(repository.ticketRequests, isEmpty);
  });

  test('ticket navigation uses personal screens', () {
    app.openTicket('tk_123');
    expect(app.current.screen, Screen.ticket);
    expect(app.current.param, 'tk_123');
    expect(app.identity, isA<PersonalIdentity>());
    app.openMyTickets();
    expect(app.current.screen, Screen.myTickets);
    for (final screen in [
      Screen.myTickets,
      Screen.ticket,
      Screen.ticketCheckoutReturn,
      Screen.ticketCheckoutCancel,
    ]) {
      expect(fanTabScreens, contains(screen));
    }
  });
}

class _ControlledTicketRepository extends DemoRepository {
  _ControlledTicketRepository({required this.auth}) : super(auth: auth);

  final FakeAuthService auth;
  int myTicketsCalls = 0;
  final ticketRequests = <String>[];
  final salesRequests = <String>[];
  final checkoutStatusRequests = <String>[];
  final cancellationRequests = <String>[];
  ({String gigId, int quantity, String? referralBandSlug})? reservationRequest;
  TicketOrderState? checkoutResult;
  int failedCheckoutCalls = 0;
  bool failLoads = false;
  Object? cancellationError;
  Completer<void>? pendingAuth;
  Completer<void>? pendingLoads;
  Completer<void>? pendingCancellation;
  Completer<TicketOrderState?>? pendingCheckout;

  @override
  Future<void> refreshAuth() => pendingAuth?.future ?? super.refreshAuth();

  @override
  Future<List<TicketSummary>> myTickets() async {
    myTicketsCalls++;
    if (failLoads) throw StateError('myTickets failed');
    final tickets = await super.myTickets();
    await pendingLoads?.future;
    return tickets;
  }

  @override
  Future<TicketSummary?> ticket(String ticketId) async {
    ticketRequests.add(ticketId);
    if (failLoads) throw StateError('ticket failed');
    final ticket = await super.ticket(ticketId);
    await pendingLoads?.future;
    return ticket;
  }

  @override
  Future<TicketReservation> reserveTickets({
    required String gigId,
    required int quantity,
    String? referralBandSlug,
  }) async {
    reservationRequest = (
      gigId: gigId,
      quantity: quantity,
      referralBandSlug: referralBandSlug,
    );
    final reservation = await super.reserveTickets(
      gigId: gigId,
      quantity: quantity,
      referralBandSlug: referralBandSlug,
    );
    await pendingLoads?.future;
    return reservation;
  }

  @override
  Future<void> cancelTicketReservation(String orderId) async {
    cancellationRequests.add(orderId);
    final error = cancellationError;
    if (error != null) throw error;
    await pendingCancellation?.future;
    await super.cancelTicketReservation(orderId);
  }

  @override
  Future<TicketOrderState?> ticketOrderStatus(String sessionId) async {
    checkoutStatusRequests.add(sessionId);
    if (failedCheckoutCalls > 0) {
      failedCheckoutCalls--;
      throw StateError('ticketOrderStatus failed');
    }
    if (pendingCheckout != null) return pendingCheckout!.future;
    return checkoutResult ?? await super.ticketOrderStatus(sessionId);
  }

  @override
  Future<TicketSales> ticketSalesForGig(String gigId) async {
    salesRequests.add(gigId);
    if (failLoads) throw StateError('ticketSalesForGig failed');
    final sales = await super.ticketSalesForGig(gigId);
    await pendingLoads?.future;
    return sales;
  }
}
