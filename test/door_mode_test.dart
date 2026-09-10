import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/ui_test_helpers.dart';

void main() {
  const launch = DoorModeLaunch(
    projectId: 'project-1',
    gigTitle: 'Riptide Release Show',
    venueName: 'The Foghorn Club',
    doorsTime: '8:00 PM',
  );

  testWidgets('viewer renders launch details and labels truncated rosters', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _DoorRepository(auth: auth, truncated: true),
      home: const DoorModeScreen(launch: launch),
    );

    expect(find.byKey(const Key('door-viewer')), findsOne);
    expect(findUiText('DOOR MODE · THE FOGHORN CLUB'), findsOne);
    expect(find.text('Riptide Release Show'), findsOne);
    expect(findUiText('DOORS 8:00 PM'), findsOne);
    expect(find.text('41 / 87 loaded'), findsOne);
    expect(find.byKey(const Key('door-roster-limited')), findsOne);
    expect(find.byKey(const Key('door-recent-empty')), findsOne);
  });

  testWidgets('manual success returns to the viewer session ledger', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _DoorRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const DoorModeScreen(launch: launch),
    );

    await tester.tap(find.byKey(const Key('door-enter-code')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('door-scanner-view')), findsOne);

    await tester.enterText(
      find.byKey(const Key('door-manual-ticket')),
      ' EP-TEST ',
    );
    await tester.tap(findUiText('CHECK TICKET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repository.lastPayload, 'EP-TEST');
    expect(find.textContaining('Mara K. checked in'), findsOne);

    await tester.tap(find.byTooltip('Back to door overview'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('door-viewer')), findsOne);
    expect(find.byKey(const Key('door-recent-empty')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(LedgerRow),
        matching: find.textContaining('Mara K.'),
      ),
      findsOne,
    );
  });

  testWidgets('successful check-in survives a roster refresh failure', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _DoorRepository(auth: auth, rosterFailures: const {2});
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const DoorModeScreen(launch: launch),
    );

    await tester.tap(find.byKey(const Key('door-enter-code')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const Key('door-manual-ticket')),
      'EP-REFRESH-FAIL',
    );
    await tester.tap(findUiText('CHECK TICKET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Mara K. checked in'), findsOne);
    expect(find.byKey(const Key('door-roster-refresh-failure')), findsOne);
    expect(find.textContaining('DO NOT SCAN AGAIN'), findsOne);
    expect(find.textContaining('Check-in failed'), findsNothing);

    await tester.tap(find.byTooltip('Back to door overview'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('door-recent-empty')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(LedgerRow),
        matching: find.textContaining('Mara K.'),
      ),
      findsOne,
    );
  });

  testWidgets('viewer surfaces a stale roster failure and can retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _DoorRepository(auth: auth, rosterFailures: const {2});
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const DoorModeScreen(launch: launch),
    );

    expect(find.text('41 / 87'), findsOne);
    await tester.tap(find.byKey(const Key('door-enter-code')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const Key('door-manual-ticket')),
      'EP-STALE-ROSTER',
    );
    await tester.tap(findUiText('CHECK TICKET'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Back to door overview'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('41 / 87'), findsOne);
    expect(find.byKey(const Key('door-roster-stale-failure')), findsOne);
    expect(findUiText('DISPLAYED COUNTS MAY BE STALE'), findsOne);
    expect(findUiText('RETRY ROSTER'), findsOne);

    await tester.tap(findUiText('RETRY ROSTER'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('door-roster-stale-failure')), findsNothing);
    expect(findUiText('DISPLAYED COUNTS MAY BE STALE'), findsNothing);
    expect(find.text('42 / 87'), findsOne);
  });

  testWidgets('initial roster failure persists across Scanner and can retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _DoorRepository(auth: auth, rosterFailures: const {1});
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const DoorModeScreen(launch: launch),
    );

    expect(find.textContaining('Door roster is unavailable'), findsOne);
    expect(findUiText('RETRY ROSTER'), findsOne);

    await tester.tap(find.byKey(const Key('door-open-scanner')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byTooltip('Back to door overview'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('Door roster is unavailable'), findsOne);
    await tester.tap(findUiText('RETRY ROSTER'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Door roster is unavailable'), findsNothing);
    expect(find.text('41 / 87'), findsOne);
  });

  testWidgets(
    'non-success results use typed status copy and do not add history',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _DoorRepository(
        auth: auth,
        result: const DoorCheckInResult(status: DoorCheckInStatus.wrongGig),
      );
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const DoorModeScreen(launch: launch),
      );

      await tester.tap(find.byKey(const Key('door-enter-code')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(
        find.byKey(const Key('door-manual-ticket')),
        'bad',
      );
      await tester.tap(findUiText('CHECK TICKET'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('That ticket belongs to a different gig.'), findsOne);
      await tester.tap(find.byTooltip('Back to door overview'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('door-recent-empty')), findsOne);
    },
  );

  const organizerLaunch = DoorModeLaunch.organizer(
    gigId: 'g8',
    gigTitle: 'Organization Ticketed Show',
    venueName: 'The Foghorn Club',
    doorsTime: '8:00 PM',
  );

  testWidgets(
    'organizer checks in a paid ticket and rejects repeat and invalid codes',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = DemoRepository(auth: auth);
      final token = await _buyDemoTicket(repository);
      expect(token, startsWith('earplug:ticket:v2:'));
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const DoorModeScreen(launch: organizerLaunch),
      );

      await tester.tap(find.byKey(const Key('door-enter-code')));
      await tester.pump(const Duration(milliseconds: 200));
      await _enterDoorCode(tester, token);

      expect(find.text('Earplug Fan checked in ✓'), findsOne);
      expect(find.text('Ticket'), findsOne);
      expect(findUiText('RSVP'), findsNothing);

      final ticket = (await repository.myTickets()).single;
      final checkedInTime = TimeOfDay.fromDateTime(
        ticket.checkedInAt!.toLocal(),
      ).format(tester.element(find.byType(DoorModeScreen)));
      await _enterDoorCode(tester, token);
      expect(find.text('Already checked in $checkedInTime'), findsOne);
      expect(find.text('Ticket'), findsNothing);

      await _enterDoorCode(tester, 'garbage');
      expect(find.text('Not a valid ticket'), findsOne);

      await tester.tap(find.byTooltip('Back to door overview'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('RSVPs 0/0 · Tickets 1/1'), findsOne);
      expect(find.byType(LedgerRow), findsOne);
      expect(find.text('Earplug Fan · $checkedInTime · door'), findsOne);
    },
  );

  testWidgets('organizer checks in a v1 RSVP with an RSVP caption', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await repository.toggleRsvp('g1');
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const DoorModeScreen(
        launch: DoorModeLaunch.organizer(
          gigId: 'g1',
          gigTitle: 'Organization RSVP Show',
          venueName: 'The Foghorn Club',
          doorsTime: '8:00 PM',
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('door-enter-code')));
    await tester.pump(const Duration(milliseconds: 200));
    await _enterDoorCode(tester, 'earplug:ticket:v1:demo-g1');

    expect(find.text('Earplug Fan checked in ✓'), findsOne);
    expect(findUiText('RSVP'), findsOne);
    expect(find.text('Ticket'), findsNothing);

    await tester.tap(find.byTooltip('Back to door overview'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('RSVPs 1/1 · Tickets 0/0'), findsOne);
    expect(
      find.descendant(
        of: find.byType(LedgerRow),
        matching: find.textContaining('Earplug Fan · '),
      ),
      findsOne,
    );
  });

  testWidgets('organizer roster refreshes both RSVP and ticket counts', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final token = await _buyDemoTicket(repository);
    await repository.toggleRsvp('g8');
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const DoorModeScreen(launch: organizerLaunch),
    );

    expect(find.text('RSVPs 0/1 · Tickets 0/1'), findsOne);
    await tester.tap(find.byKey(const Key('door-enter-code')));
    await tester.pump(const Duration(milliseconds: 200));
    await _enterDoorCode(tester, 'earplug:ticket:v1:demo-g8');
    expect(findUiText('RSVP'), findsOne);
    await _enterDoorCode(tester, token);
    expect(find.text('Ticket'), findsOne);

    await tester.tap(find.byTooltip('Back to door overview'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: find.byKey(const Key('door-organizer-roster')),
        matching: find.text('RSVPs 1/1 · Tickets 1/1'),
        matchRoot: true,
      ),
      findsOne,
    );
    expect(find.byType(LedgerRow), findsNWidgets(2));
  });

  testWidgets('showOrganizerDoorMode pushes the organizer door screen', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showOrganizerDoorMode(
              context,
              gigId: 'g8',
              gigTitle: 'Organization Ticketed Show',
              venueName: 'The Foghorn Club',
              doorsTime: '8:00 PM',
            ),
            child: const Text('Open organizer door'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open organizer door'));
    await tester.pumpAndSettle();

    expect(find.byType(DoorModeScreen), findsOne);
    expect(find.text('Organization Ticketed Show'), findsOne);
    expect(find.text('RSVPs 0/0 · Tickets 0/0'), findsOne);

    await tester.tap(find.byTooltip('Close Door Mode'));
    await tester.pumpAndSettle();
    expect(find.byType(DoorModeScreen), findsNothing);
    expect(find.text('Open organizer door'), findsOne);
  });
}

Future<String> _buyDemoTicket(DemoRepository repository) async {
  final reservation = await repository.reserveTickets(gigId: 'g8', quantity: 1);
  final checkout = await repository.startTicketCheckout(reservation.orderId);
  await repository.simulateTicketCheckoutCompleted(checkout.sessionId);
  return (await repository.myTickets()).single.token;
}

Future<void> _enterDoorCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('door-manual-ticket')), code);
  await tester.tap(findUiText('CHECK TICKET'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

class _DoorRepository extends DemoRepository {
  _DoorRepository({
    required super.auth,
    this.truncated = false,
    this.rosterFailures = const {},
    this.result = const DoorCheckInResult(
      status: DoorCheckInStatus.checkedIn,
      fanName: 'Mara K.',
    ),
  });

  final bool truncated;
  final Set<int> rosterFailures;
  final DoorCheckInResult result;
  String? lastPayload;
  int checkedIn = 41;
  int rosterCalls = 0;

  @override
  Future<DoorRoster> doorRoster(String projectId) async {
    rosterCalls++;
    if (rosterFailures.contains(rosterCalls)) {
      throw StateError('Roster unavailable');
    }
    return DoorRoster(total: 87, checkedIn: checkedIn, truncated: truncated);
  }

  @override
  Future<DoorCheckInResult> checkInTicket({
    required String projectId,
    required String payload,
  }) async {
    lastPayload = payload;
    if (result.status == DoorCheckInStatus.checkedIn) checkedIn++;
    return result;
  }
}
