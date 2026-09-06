import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/ticket_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'support/harness.dart';

void main() {
  late FakeAuthService auth;
  late _TicketRepository repository;

  setUp(() async {
    auth = FakeAuthService();
    await auth.signInDemo();
    repository = _TicketRepository(auth: auth);
  });

  testWidgets('valid ticket displays its QR token and opens the event', (
    tester,
  ) async {
    late TicketSummary ticket;
    final harness = await pumpApp(
      tester,
      home: Scaffold(
        body: Builder(builder: (_) => TicketDetailScreen(ticketId: ticket.id)),
      ),
      auth: auth,
      repository: repository,
      beforePump: (app) async {
        app.hostedUrlLauncher = (_) async {};
        final reservation = await app.reserveTickets('g8', 1);
        final sessionId = await app.startTicketCheckout(reservation.orderId);
        await repository.simulateTicketCheckoutCompleted(sessionId);
        await app.loadMyTickets();
        ticket = app.myTickets.single;
        app.openTicket(ticket.id);
      },
    );

    final qr = tester.widget<QrImageView>(
      find.byKey(const Key('ticket-detail-qr')),
    );
    // qr_flutter 4.1 keeps data private. Compare the rendered QR with the
    // expected token to verify what a scanner will actually read.
    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(const Key('ticket-detail-qr')),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as QrPainter;
    final expected = QrPainter(
      data: ticket.token,
      version: QrVersions.auto,
      gapless: qr.gapless,
      eyeStyle: qr.eyeStyle,
      dataModuleStyle: qr.dataModuleStyle,
    );
    await tester.runAsync(() async {
      final actualImage = await painter.toImageData(256);
      final expectedImage = await expected.toImageData(256);
      expect(
        actualImage!.buffer.asUint8List(),
        orderedEquals(expectedImage!.buffer.asUint8List()),
      );
    });
    expect(qr.backgroundColor, Colors.white);
    expect(qr.eyeStyle.color, Colors.black);
    expect(qr.dataModuleStyle.color, Colors.black);
    expect(find.text(ticket.gig.title), findsOneWidget);
    expect(find.text(ticket.gig.venueName), findsOneWidget);
    expect(find.textContaining(dateLabel(ticket.gig.startsAt)), findsOneWidget);
    expect(find.text('VALID'), findsOneWidget);
    expect(find.text('Show this at the door'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    final eventButton = find.byKey(const Key('ticket-detail-event'));
    await tester.ensureVisible(eventButton);
    await tester.tap(eventButton);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, ticket.gig.id);
  });

  for (final checkedInAt in [DateTime(2026, 9, 5, 20, 30), null]) {
    testWidgets('used ticket hides QR with check-in time $checkedInAt', (
      tester,
    ) async {
      repository.tickets['ticket'] = _ticket(
        status: TicketStatus.used,
        checkedInAt: checkedInAt,
      );
      await pumpApp(
        tester,
        home: const Scaffold(body: TicketDetailScreen(ticketId: 'ticket')),
        auth: auth,
        repository: repository,
      );

      expect(find.byKey(const Key('ticket-detail-qr')), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('CHECKED IN'), findsOneWidget);
      expect(
        find.text(
          checkedInAt == null
              ? 'Checked in'
              : 'Checked in ${dateLabel(checkedInAt)} · '
                    '${timeLabel(TimeOfDay.fromDateTime(checkedInAt))}',
        ),
        findsOneWidget,
      );
    });
  }

  for (final (status, message) in [
    (TicketStatus.refunded, 'This ticket was refunded.'),
    (TicketStatus.cancelled, 'This ticket was cancelled.'),
    (TicketStatus.unknown, 'This ticket is unavailable.'),
  ]) {
    testWidgets('${status.name} ticket shows a banner without a QR', (
      tester,
    ) async {
      repository.tickets['ticket'] = _ticket(status: status);
      await pumpApp(
        tester,
        home: const Scaffold(body: TicketDetailScreen(ticketId: 'ticket')),
        auth: auth,
        repository: repository,
      );

      expect(find.byKey(const Key('ticket-detail-qr')), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text(message), findsOneWidget);
    });
  }

  testWidgets('refresh replaces a cached QR when the ticket is checked in', (
    tester,
  ) async {
    repository.tickets['ticket'] = _ticket();
    await pumpApp(
      tester,
      home: const Scaffold(body: TicketDetailScreen(ticketId: 'ticket')),
      auth: auth,
      repository: repository,
    );
    expect(find.byKey(const Key('ticket-detail-qr')), findsOneWidget);
    expect(repository.ticketRequests, ['ticket']);
    repository.tickets['ticket'] = _ticket(status: TicketStatus.used);

    await tester.tap(find.byKey(const Key('ticket-detail-refresh')));
    await tester.pumpAndSettle();

    expect(repository.ticketRequests, ['ticket', 'ticket']);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Checked in'), findsOneWidget);
  });

  testWidgets('changing ticketId loads the new ticket on the same screen', (
    tester,
  ) async {
    final ticketId = ValueNotifier('ticket');
    addTearDown(ticketId.dispose);
    repository.tickets['ticket'] = _ticket();
    repository.tickets['other'] = _ticket(
      id: 'other',
      status: TicketStatus.refunded,
    );
    await pumpApp(
      tester,
      home: Scaffold(
        body: ValueListenableBuilder(
          valueListenable: ticketId,
          builder: (_, id, _) => TicketDetailScreen(ticketId: id),
        ),
      ),
      auth: auth,
      repository: repository,
    );
    expect(find.byType(QrImageView), findsOneWidget);

    ticketId.value = 'other';
    await tester.pumpAndSettle();

    expect(repository.ticketRequests, ['ticket', 'other']);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('This ticket was refunded.'), findsOneWidget);
  });

  testWidgets('missing ticket finishes loading and offers a back action', (
    tester,
  ) async {
    final pending = Completer<TicketSummary?>();
    repository.pendingTicket = pending;
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: TicketDetailScreen(ticketId: 'missing')),
      auth: auth,
      repository: repository,
      beforePump: (app) {
        app.resetTo(Screen.myGigs);
        app.openTicket('missing');
      },
      pumpFor: Duration.zero,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(null);
    await tester.pumpAndSettle();

    expect(find.text("This ticket isn't available"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('BACK'));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.myGigs);
  });
}

TicketSummary _ticket({
  String id = 'ticket',
  TicketStatus status = TicketStatus.valid,
  DateTime? checkedInAt,
}) => TicketSummary(
  id: id,
  orderId: 'order',
  gigId: 'g8',
  token: 'earplug:ticket:v2:$id',
  status: status,
  checkedInAt: checkedInAt,
  createdAt: DateTime(2026, 9),
  gig: TicketGigSummary(
    id: 'g8',
    title: 'Ticket detail show',
    startsAt: DateTime(2026, 9, 5, 21),
    doorsAt: DateTime(2026, 9, 5, 20),
    venueName: 'Test venue',
    lifecycle: GigLifecycle.published,
  ),
);

class _TicketRepository extends DemoRepository {
  _TicketRepository({required super.auth});

  final tickets = <String, TicketSummary>{};
  final ticketRequests = <String>[];
  Completer<TicketSummary?>? pendingTicket;

  @override
  Future<TicketSummary?> ticket(String ticketId) async {
    ticketRequests.add(ticketId);
    final pending = pendingTicket;
    if (pending != null) return pending.future;
    return tickets[ticketId] ?? await super.ticket(ticketId);
  }
}
