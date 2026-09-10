import 'package:earplug/app_state.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

void main() {
  late FakeAuthService auth;
  late _WalletRepository repository;

  setUp(() async {
    auth = FakeAuthService();
    await auth.signInDemo();
    repository = _WalletRepository(auth: auth);
  });

  testWidgets('wallet lazily loads paid tickets and opens a ticket', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: MyGigsScreen()),
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.hostedUrlLauncher = (_) async {};
        final reservation = await app.reserveTickets('g8', 2);
        final sessionId = await app.startTicketCheckout(reservation.orderId);
        await repository.simulateTicketCheckoutCompleted(sessionId);
        expect(app.myTicketsLoaded, isFalse);
      },
    );
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pumpAndSettle();

    expect(harness.app.myTicketsLoaded, isTrue);
    expect(repository.walletLoads, 1);
    expect(harness.app.myTickets, hasLength(2));
    final section = find.byWidgetPredicate(
      (widget) => widget is SectionBar && widget.label == 'TICKETS',
    );
    expect(tester.widget<SectionBar>(section).count, 2);
    expect(
      tester.getTopLeft(section).dy,
      lessThan(tester.getTopLeft(find.textContaining('UPCOMING RSVPS')).dy),
    );
    for (final ticket in harness.app.myTickets) {
      final card = find.byKey(ValueKey('ticket-${ticket.id}'));
      expect(tester.widget(card), isA<EpCard>());
      for (final label in [ticket.gig.title, ticket.gig.venueName, 'VALID']) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: card, matching: find.byType(DateBlock)),
        findsOneWidget,
      );
    }
    expect(find.byType(TextField), findsNothing);

    final ticket = harness.app.myTickets.first;
    await tester.tap(find.byKey(ValueKey('ticket-${ticket.id}')));
    await tester.pumpAndSettle();

    expect(harness.app.current.screen, Screen.ticket);
    expect(harness.app.current.param, ticket.id);
    expect(repository.walletLoads, 1);
  });

  testWidgets('empty wallet explains where paid tickets will appear', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: MyGigsScreen()),
      auth: auth,
      repository: repository,
    );

    expect(harness.app.myTicketsLoaded, isTrue);
    expect(repository.walletLoads, 1);
    expect(
      find.text('No tickets yet · paid shows list them here'),
      findsOneWidget,
    );
    final section = tester.widget<SectionBar>(
      find.byWidgetPredicate(
        (widget) => widget is SectionBar && widget.label == 'TICKETS',
      ),
    );
    expect(section.count, 0);
  });

  testWidgets('wallet includes only upcoming valid and checked-in tickets', (
    tester,
  ) async {
    final now = DateTime.now();
    final future = now.add(const Duration(days: 2));
    final past = now.subtract(const Duration(days: 2));
    repository.tickets = [
      _ticket('valid', TicketStatus.valid, future),
      _ticket('used', TicketStatus.used, future),
      _ticket('refunded', TicketStatus.refunded, future),
      _ticket('cancelled', TicketStatus.cancelled, future),
      _ticket('unknown', TicketStatus.unknown, future),
      _ticket('past-valid', TicketStatus.valid, past),
      _ticket('past-used', TicketStatus.used, past),
    ];
    await pumpApp(
      tester,
      home: const Scaffold(body: MyGigsScreen()),
      auth: auth,
      repository: repository,
    );
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ticket-valid')), findsOneWidget);
    final used = find.byKey(const ValueKey('ticket-used'));
    expect(used, findsOneWidget);
    expect(
      find.descendant(of: used, matching: findUiText('CHECKED IN')),
      findsOneWidget,
    );
    for (final id in [
      'refunded',
      'cancelled',
      'unknown',
      'past-valid',
      'past-used',
    ]) {
      expect(find.byKey(ValueKey('ticket-$id')), findsNothing);
    }
    final section = tester.widget<SectionBar>(
      find.byWidgetPredicate(
        (widget) => widget is SectionBar && widget.label == 'TICKETS',
      ),
    );
    expect(section.count, 2);
  });
}

TicketSummary _ticket(String id, TicketStatus status, DateTime startsAt) =>
    TicketSummary(
      id: id,
      orderId: 'order-$id',
      gigId: 'g8',
      token: 'earplug:ticket:v2:$id',
      status: status,
      createdAt: startsAt.subtract(const Duration(days: 7)),
      gig: TicketGigSummary(
        id: 'g8',
        title: 'Wallet test show',
        startsAt: startsAt,
        venueName: 'Test venue',
        lifecycle: GigLifecycle.published,
      ),
    );

class _WalletRepository extends StubRepository {
  _WalletRepository({required super.auth}) {
    wraps<List<TicketSummary>>('myTickets', (real) => tickets ?? real);
  }

  List<TicketSummary>? tickets;

  int get walletLoads => callsTo('myTickets');
}
