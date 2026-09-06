import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/ticket_return.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  late FakeAuthService auth;
  late _ControlledTicketReturnRepository repository;

  setUp(() async {
    auth = FakeAuthService();
    await auth.signInDemo();
    repository = _ControlledTicketReturnRepository(auth: auth);
  });

  for (final quantity in [1, 2]) {
    testWidgets(
      'return polls until $quantity tickets are paid and opens wallet',
      (tester) async {
        late String sessionId;
        final harness = await pumpApp(
          tester,
          home: Builder(
            builder: (_) => TicketCheckoutReturnScreen(
              sessionId: sessionId,
              interval: const Duration(milliseconds: 5),
              timeout: const Duration(seconds: 2),
            ),
          ),
          auth: auth,
          repository: repository,
          beforePump: (app) async {
            app.hostedUrlLauncher = (_) async {};
            final reservation = await app.reserveTickets('g8', quantity);
            sessionId = await app.startTicketCheckout(reservation.orderId);
            app.go(Screen.ticketCheckoutReturn, sessionId);
          },
          pumpFor: Duration.zero,
        );

        expect(find.text('Confirming your payment…'), findsOneWidget);
        expect(find.text('This usually takes a few seconds.'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(repository.checkoutRequests, [sessionId]);

        await repository.simulateTicketCheckoutCompleted(sessionId);
        await tester.pump(const Duration(milliseconds: 5));
        await tester.pumpAndSettle();

        expect(find.text("You're in"), findsOneWidget);
        final eventTitle = harness.app.gig('g8')!.title;
        final noun = quantity == 1 ? 'ticket' : 'tickets';
        expect(find.text('$quantity $noun for $eventTitle'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(repository.checkoutRequests.length, greaterThanOrEqualTo(2));
        expect(harness.app.pendingReservation, isNull);
        expect(harness.app.myTickets, hasLength(quantity));

        await tester.tap(find.byKey(const Key('ticket-return-wallet')));
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.myTickets);
      },
    );
  }

  testWidgets(
    'paid return uses a generic title when the event is unavailable',
    (tester) async {
      repository.checkoutResult = _order(
        TicketOrderStatus.paid,
        gigId: 'missing-gig',
      );
      await pumpApp(
        tester,
        home: const TicketCheckoutReturnScreen(sessionId: 'cs_paid'),
        auth: auth,
        repository: repository,
      );

      expect(find.text("You're in"), findsOneWidget);
      expect(find.text('1 ticket for the show'), findsOneWidget);
    },
  );

  for (final status in [
    TicketOrderStatus.expired,
    TicketOrderStatus.cancelled,
  ]) {
    testWidgets('${status.name} hold explains expiry and opens the event', (
      tester,
    ) async {
      repository.checkoutResult = _order(status);
      final harness = await pumpApp(
        tester,
        home: const TicketCheckoutReturnScreen(sessionId: 'cs_expired'),
        auth: auth,
        repository: repository,
      );

      expect(
        find.text('This hold expired before payment finished'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket-return-wallet')), findsNothing);
      await tester.tap(find.byKey(const Key('ticket-return-event')));
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.gig);
      expect(harness.app.current.param, 'g8');
    });
  }

  testWidgets('refunded checkout explains its status and returns home', (
    tester,
  ) async {
    repository.checkoutResult = _order(TicketOrderStatus.refunded);
    final harness = await pumpApp(
      tester,
      home: const TicketCheckoutReturnScreen(sessionId: 'cs_refunded'),
      auth: auth,
      repository: repository,
      beforePump: (app) => app.resetTo(Screen.ticketCheckoutReturn),
    );

    expect(find.text('This order was refunded'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ticket-return-back')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.home);
  });

  testWidgets('unavailable checkout offers a terminal back action', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const TicketCheckoutReturnScreen(
        sessionId: 'missing',
        interval: Duration(milliseconds: 5),
        timeout: Duration(milliseconds: 25),
      ),
      auth: auth,
      repository: repository,
      beforePump: (app) => app.resetTo(Screen.ticketCheckoutReturn),
    );

    expect(find.text("This checkout isn't available"), findsOneWidget);
    expect(find.byKey(const Key('ticket-return-wallet')), findsNothing);
    expect(find.byKey(const Key('ticket-return-retry')), findsNothing);
    await tester.tap(find.byKey(const Key('ticket-return-back')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.home);
  });

  testWidgets('cancel retry launches Checkout for the specified order', (
    tester,
  ) async {
    late String orderId;
    final launched = <String>[];
    final harness = await pumpApp(
      tester,
      home: Builder(
        builder: (_) => TicketCheckoutCancelScreen(orderId: orderId),
      ),
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.hostedUrlLauncher = (url) async {
          launched.add(url);
        };
        orderId = (await app.reserveTickets('g8', 1)).orderId;
        app.go(Screen.ticketCheckoutCancel, orderId);
      },
    );

    expect(find.text('Payment cancelled'), findsOneWidget);
    expect(
      find.text('Your hold is still active for a few minutes'),
      findsOneWidget,
    );
    expect(launched, isEmpty);
    await tester.tap(find.byKey(const Key('ticket-cancel-retry')));
    await tester.pumpAndSettle();

    expect(repository.checkoutOrders, [orderId]);
    expect(launched, ['https://demo.stripe/tickets/$orderId']);
    expect(harness.app.pendingReservation?.orderId, orderId);
  });

  testWidgets('release hold waits for cancellation before returning home', (
    tester,
  ) async {
    late String orderId;
    final pending = Completer<void>();
    repository.pendingCancellation = pending;
    final harness = await pumpApp(
      tester,
      home: Builder(
        builder: (_) => TicketCheckoutCancelScreen(orderId: orderId),
      ),
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        orderId = (await app.reserveTickets('g8', 1)).orderId;
        app.go(Screen.ticketCheckoutCancel, orderId);
      },
    );

    final releaseButton = find.byKey(const Key('ticket-cancel-release'));
    expect(tester.widget<EpButton>(releaseButton).kind, EpButtonKind.ghost);
    await tester.tap(releaseButton);
    await tester.pump();
    expect(repository.cancellationRequests, [orderId]);
    expect(harness.app.pendingReservation, isNull);
    expect(harness.app.current.screen, Screen.ticketCheckoutCancel);

    pending.complete();
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.home);
    expect((await harness.app.loadTicketSales('g8'))?.reserved, 0);
  });
}

TicketOrderState _order(TicketOrderStatus status, {String gigId = 'g8'}) =>
    TicketOrderState(
      orderId: 'order',
      gigId: gigId,
      status: status,
      quantity: 1,
      totalMinor: 1000,
      currency: 'usd',
    );

class _ControlledTicketReturnRepository extends DemoRepository {
  _ControlledTicketReturnRepository({required super.auth});

  TicketOrderState? checkoutResult;
  Completer<void>? pendingCancellation;
  final checkoutRequests = <String>[];
  final checkoutOrders = <String>[];
  final cancellationRequests = <String>[];

  @override
  Future<TicketOrderState?> ticketOrderStatus(String sessionId) async {
    checkoutRequests.add(sessionId);
    return checkoutResult ?? await super.ticketOrderStatus(sessionId);
  }

  @override
  Future<({String url, String sessionId})> startTicketCheckout(String orderId) {
    checkoutOrders.add(orderId);
    return super.startTicketCheckout(orderId);
  }

  @override
  Future<void> cancelTicketReservation(String orderId) async {
    cancellationRequests.add(orderId);
    await pendingCancellation?.future;
    return super.cancelTicketReservation(orderId);
  }
}
