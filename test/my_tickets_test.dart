import 'package:earplug/app_state.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

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
    await _selectTickets(tester, count: 2);
    for (final ticket in harness.app.myTickets) {
      final card = find.byKey(ValueKey('ticket-${ticket.id}'));
      expect(tester.widget(card), isA<ExploreEventSnapshotRow>());
      for (final label in [
        ticket.gig.title.toUpperCase(),
        ticket.gig.venueName,
      ]) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            eventDateLine(
              ticket.gig.startsAt,
              doorsLabel: timeLabel(
                TimeOfDay.fromDateTime(
                  ticket.gig.doorsAt ?? ticket.gig.startsAt,
                ),
              ),
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('ticket-status-${ticket.id}')),
          matching: find.text('TICKET · VALID'),
        ),
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

  testWidgets('empty wallet and saved list stay quiet with an upcoming RSVP', (
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
    expect(harness.app.upcomingRsvpGigs, isNotEmpty);
    await _selectTickets(tester, count: 0);
    expect(find.text('No tickets yet.'), findsOneWidget);
    expect(find.text('FIND A SHOW'), findsNothing);

    for (final id in harness.app.saved.toList()) {
      harness.app.toggleSave(id);
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('SAVED · 0'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing saved yet.'), findsOneWidget);
    final savedNote = find
        .ancestor(
          of: find.text('Nothing saved yet.'),
          matching: find.byType(Column),
        )
        .first;
    expect(
      find.descendant(of: savedNote, matching: find.text('FIND A SHOW')),
      findsNothing,
    );
  });

  testWidgets('wallet includes only upcoming valid and checked-in tickets', (
    tester,
  ) async {
    final now = DateTime.now();
    final future = DateTime(now.year, now.month, now.day + 2, 21);
    final past = now.subtract(const Duration(days: 2));
    repository.tickets = [
      _ticket(
        'valid',
        TicketStatus.valid,
        future,
        doorsAt: future.subtract(const Duration(hours: 1, minutes: 30)),
      ),
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

    await _selectTickets(tester, count: 2);

    expect(find.byKey(const ValueKey('ticket-valid')), findsOneWidget);
    final used = find.byKey(const ValueKey('ticket-used'));
    expect(used, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-status-used')),
        matching: find.text('TICKET · CHECKED IN'),
      ),
      findsOneWidget,
    );
    final datePrefix =
        '${weekdayNamesUpper[future.weekday - 1]}, '
        '${monthNamesUpper[future.month - 1]} ${future.day} AT';
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ticket-valid')),
        matching: find.text('$datePrefix 7:30PM'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: used, matching: find.text('$datePrefix 9PM')),
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
  });
}

Future<void> _selectTickets(WidgetTester tester, {required int count}) async {
  final tabs = tester.widget<EpSegmentTabs>(find.byType(EpSegmentTabs));
  expect(tabs.labels[1], 'Tickets · $count');
  final segment = find.text('TICKETS · $count');
  await tester.ensureVisible(segment);
  await tester.tap(segment);
  await tester.pumpAndSettle();
  expect(tester.widget<EpSegmentTabs>(find.byType(EpSegmentTabs)).selected, 1);
}

TicketSummary _ticket(
  String id,
  TicketStatus status,
  DateTime startsAt, {
  DateTime? doorsAt,
}) => TicketSummary(
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
    doorsAt: doorsAt,
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
