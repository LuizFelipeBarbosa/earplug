import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/screens/gig_manager.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/band_ticket_sales_sheet.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('manager groups every lifecycle and uses refreshed row grammar', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ManagerRepository(auth: auth),
      home: const Scaffold(body: GigManagerScreen()),
    );

    expect(find.text('GIGS'), findsOne);

    await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gig-project-published-rsvp')), findsOne);
    expect(find.byType(DateBlock), findsWidgets);
    expect(find.text('PUBLISHED'), findsWidgets);
    expect(find.textContaining('going'), findsOne);
    expect(find.byKey(const Key('gig-door-published-rsvp')), findsOne);
    expect(find.byKey(const Key('gig-door-published-external')), findsOne);

    await tester.scrollUntilVisible(
      find.byType(GhostDraftRow),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(GhostDraftRow), findsOne);
    expect(
      find.textContaining('FINISH NAME, DATE AND TIMES, VENUE, LINEUP'),
      findsOne,
    );

    final pastSegment = find.byKey(const Key('band-gigs-seg-past'));
    await tester.scrollUntilVisible(
      pastSegment,
      -180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(pastSegment);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('CANCELLED'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('gig-project-cancelled')), findsOne);

    for (
      var index = 0;
      index < 4 && find.textContaining('PAST ·').evaluate().isEmpty;
      index++
    ) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump();
    }
    expect(find.textContaining('PAST ·'), findsOne);
    expect(find.byType(LedgerRow), findsWidgets);
  });

  testWidgets('published overflow keeps lifecycle actions with only delete red', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ManagerRepository(auth: auth),
      home: const Scaffold(body: GigManagerScreen()),
    );

    await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('gig-actions-published-rsvp')));
    await tester.pumpAndSettle();

    expect(find.byType(EpActionSheet), findsOne);
    expect(find.text('Duplicate'), findsOne);
    expect(find.text('Unpublish…'), findsOne);
    expect(find.text('Cancel gig…'), findsOne);
    expect(find.text('Delete'), findsOne);
    expect(
      tester.widget<Text>(find.text('Delete')).style?.color,
      Ep.destructive,
    );
    expect(
      tester.widget<Text>(find.text('Cancel gig…')).style?.color,
      isNot(Ep.destructive),
    );

    await tester.tap(find.text('Cancel gig…'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel gig?'), findsOne);
    expect(
      find.text(
        'The gig leaves discovery but its public page stays available as cancelled.',
      ),
      findsOne,
    );
  });

  testWidgets('paid gig cancellation explains refunds when tickets are sold', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ManagerRepository(
        auth: auth,
        salesResponse: Future.value(_ManagerRepository.paidSales),
      ),
      home: const Scaffold(body: GigManagerScreen()),
    );

    await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
    await tester.pumpAndSettle();
    final actions = find.byKey(const Key('gig-actions-published-paid'));
    await tester.scrollUntilVisible(
      actions,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(actions);
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel gig…'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel gig?'), findsOne);
    expect(
      find.text(
        'Sold tickets are refunded in full and buyers are emailed. The gig leaves discovery but its public page stays available as cancelled.',
      ),
      findsOne,
    );
    expect(
      find.text(
        'The gig leaves discovery but its public page stays available as cancelled.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'card-face actions preserve edit, preview, and Door launch data',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ManagerRepository(auth: auth);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: GigManagerScreen()),
      );

      await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('gig-edit-published-rsvp')));
      await tester.pump();
      expect(harness.app.current.screen, Screen.gigCreate);

      await tester.tap(find.byKey(const Key('gig-door-published-rsvp')));
      await tester.pumpAndSettle();
      expect(find.byType(DoorModeScreen), findsOne);
      expect(find.text('RIPTIDE RELEASE SHOW'), findsOne);
      expect(find.text('DOOR MODE · THE FOGHORN CLUB'), findsOne);
      expect(repository.organizerRosterRequests, ['g2']);
      expect(repository.projectRosterRequests, isEmpty);
    },
  );

  testWidgets('paid sales load once and open a breakdown without Delete', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final response = Completer<TicketSales>();
    final repository = _ManagerRepository(
      auth: auth,
      salesResponse: response.future,
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: GigManagerScreen()),
    );

    await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
    await tester.pumpAndSettle();
    final actions = find.byKey(const Key('gig-actions-published-paid'));
    await tester.scrollUntilVisible(
      actions,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    final sales = find.byKey(const Key('gig-sales-published-paid'));
    expect(sales, findsNothing);
    expect(repository.salesRequests, ['g-paid']);

    await harness.app.refreshManagedGigs();
    await tester.pumpAndSettle();
    expect(repository.salesRequests, ['g-paid']);

    response.complete(_ManagerRepository.paidSales);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(sales).data, 'SALES · 12/50');
    await harness.app.refreshManagedGigs();
    await tester.pumpAndSettle();
    expect(repository.salesRequests, ['g-paid']);

    await tester.ensureVisible(actions);
    await tester.tap(actions);
    await tester.pumpAndSettle();
    expect(find.text('Sales'), findsOne);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Duplicate'), findsOne);
    expect(find.text('Unpublish…'), findsOne);
    expect(find.text('Cancel gig…'), findsOne);

    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('band-ticket-sales-sheet'));
    expect(sheet, findsOne);
    for (final text in [
      'PAID TICKET SHOW',
      'Sold',
      '12/50',
      'Gross',
      r'$260.00',
      'EarPlug fee',
      r'$26.00',
      'Refunds',
      r'$20.00',
      'Net',
      'Orders',
      '6',
    ]) {
      expect(find.descendant(of: sheet, matching: find.text(text)), findsOne);
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('band-ticket-sales-net'))).data,
      r'$216.00',
    );
    expect(repository.salesRequests, ['g-paid']);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('paid projects with no sales still offer Delete', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ManagerRepository(
        auth: auth,
        salesResponse: Future.value(_ManagerRepository.zeroSales),
      ),
      home: const Scaffold(body: GigManagerScreen()),
    );

    await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
    await tester.pumpAndSettle();
    final actions = find.byKey(const Key('gig-actions-published-paid'));
    await tester.scrollUntilVisible(
      actions,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('SALES · 0/50'), findsOne);
    await tester.ensureVisible(actions);
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();
    expect(find.text('Sales'), findsOne);
    expect(find.text('Delete'), findsOne);
  });

  testWidgets('sales sheet loads an empty cache and hides zero refunds', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final response = Completer<TicketSales>();
    final repository = _ManagerRepository(
      auth: auth,
      salesResponse: response.future,
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBandTicketSalesSheet(
              context,
              gigId: 'g-paid',
              title: 'Paid Ticket Show',
            ),
            child: const Text('SALES'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('SALES'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final sheet = find.byKey(const Key('band-ticket-sales-sheet'));
    expect(sheet, findsOne);
    expect(
      find.descendant(
        of: sheet,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOne,
    );
    expect(repository.salesRequests, ['g-paid']);

    response.complete(_ManagerRepository.zeroSales);
    await tester.pumpAndSettle();
    expect(find.text('0/50'), findsOne);
    expect(find.text('Refunds'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('band-ticket-sales-net'))).data,
      r'$0.00',
    );
  });

  for (final (projectId, gigId) in [
    ('published-external', 'not-loaded'),
    ('published-paid', 'g-paid'),
  ]) {
    testWidgets('$projectId launches the public gig door roster', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final repository = _ManagerRepository(auth: auth);
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: GigManagerScreen()),
      );

      await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
      await tester.pumpAndSettle();
      final door = find.byKey(ValueKey('gig-door-$projectId'));
      await tester.scrollUntilVisible(
        door,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(door);
      await tester.pumpAndSettle();
      await tester.tap(door);
      await tester.pumpAndSettle();
      expect(find.byType(DoorModeScreen), findsOne);
      expect(repository.organizerRosterRequests, [gigId]);
      expect(repository.projectRosterRequests, isEmpty);
    });
  }

  testWidgets(
    'published projects without a public id keep the project roster',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ManagerRepository(auth: auth);
      repository.projects
        ..clear()
        ..add(
          _project(
            id: 'legacy',
            title: 'Legacy Show',
            status: GigProjectStatus.published,
            ticketing: Ticketing.paid,
          ),
        );
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: const Scaffold(body: GigManagerScreen()),
      );

      await tester.tap(find.byKey(const Key('band-gigs-seg-booked')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gig-door-legacy')));
      await tester.pumpAndSettle();
      expect(find.byType(DoorModeScreen), findsOne);
      expect(repository.projectRosterRequests, ['legacy']);
      expect(repository.organizerRosterRequests, isEmpty);
    },
  );
}

class _ManagerRepository extends DemoRepository {
  _ManagerRepository({required super.auth, this.salesResponse});

  final Future<TicketSales>? salesResponse;
  final salesRequests = <String>[];
  final organizerRosterRequests = <String>[];
  final projectRosterRequests = <String>[];

  static const paidSales = TicketSales(
    capacity: 50,
    sold: 12,
    reserved: 2,
    available: 36,
    ordersPaid: 6,
    grossMinor: 26000,
    feeMinor: 2600,
    netMinor: 21600,
    currency: 'usd',
    refundedMinor: 2000,
    refundedOrgMinor: 1800,
  );

  static const zeroSales = TicketSales(
    capacity: 50,
    sold: 0,
    reserved: 0,
    available: 50,
    ordersPaid: 0,
    grossMinor: 0,
    feeMinor: 0,
    netMinor: 0,
    currency: 'usd',
  );

  late final List<GigProject> projects = [
    _project(
      id: 'published-rsvp',
      title: 'Riptide Release Show',
      status: GigProjectStatus.published,
      ticketing: Ticketing.rsvp,
      publicGigId: 'g2',
    ),
    _project(
      id: 'published-external',
      title: 'External Ticket Show',
      status: GigProjectStatus.published,
      ticketing: Ticketing.external,
      publicGigId: 'not-loaded',
    ),
    _project(
      id: 'published-paid',
      title: 'Paid Ticket Show',
      status: GigProjectStatus.published,
      ticketing: Ticketing.paid,
      publicGigId: 'g-paid',
    ),
    _project(id: 'draft', status: GigProjectStatus.draft, incomplete: true),
    _project(
      id: 'cancelled',
      title: 'Cancelled Show',
      status: GigProjectStatus.cancelled,
    ),
  ];

  @override
  Future<List<GigProject>> manageGigs(String bandId) async => projects;

  @override
  Future<GigProject> getGigProject(String projectId) async =>
      projects.firstWhere((project) => project.id == projectId);

  @override
  Future<DoorRoster> doorRoster(String projectId) async {
    projectRosterRequests.add(projectId);
    return const DoorRoster(total: 87, checkedIn: 41, truncated: false);
  }

  @override
  Future<DoorCounts> organizerDoorRoster(String gigId) async {
    organizerRosterRequests.add(gigId);
    return const DoorCounts(
      rsvpTotal: 87,
      rsvpCheckedIn: 41,
      ticketsSold: 12,
      ticketsCheckedIn: 3,
      truncated: false,
    );
  }

  @override
  Future<TicketSales> ticketSalesForGig(String gigId) async {
    salesRequests.add(gigId);
    if (gigId != 'g-paid') return zeroSales;
    return salesResponse == null ? paidSales : await salesResponse!;
  }
}

GigProject _project({
  required String id,
  String? title,
  required GigProjectStatus status,
  Ticketing ticketing = Ticketing.rsvp,
  String? publicGigId,
  bool incomplete = false,
}) {
  final startsAt = DateTime.now().add(const Duration(days: 2));
  return GigProject(
    id: id,
    bandId: 'b1',
    publicGigId: publicGigId,
    status: status,
    revision: 2,
    publishedRevision: status == GigProjectStatus.published ? 2 : null,
    title: incomplete ? null : title,
    doorsAt: incomplete ? null : startsAt.subtract(const Duration(hours: 1)),
    startsAt: incomplete ? null : startsAt,
    venueId: incomplete ? null : 'v1',
    price: 0,
    flyKey: 'blue',
    overlay: true,
    desc: '',
    ticketing: ticketing,
    ageRequirement: AgeRequirement.allAges,
    cap: 'No cap',
    updatedAt: DateTime.now(),
    performers: incomplete
        ? const []
        : const [
            GigPerformer(
              id: 'performer',
              kind: GigPerformerKind.band,
              name: 'Foghorn Diet',
              role: GigPerformerRole.headliner,
              bandId: 'b1',
            ),
          ],
  );
}
