import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/screens/gig_manager.dart';
import 'package:earplug/screens/hosted_gig.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_applications_tab.dart';
import 'package:earplug/widgets/band_discover_tab.dart';
import 'package:earplug/widgets/band_my_gigs_tab.dart';
import 'package:earplug/widgets/band_ticket_sales_sheet.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  for (final empty in [false, true]) {
    testWidgets('GIGS lands on MY GIGS at 390x844 (empty: $empty)', (
      tester,
    ) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = StubRepository(auth: auth);
      if (empty) repository.returns('bandBookings', <Booking>[]);
      await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        size: const Size(390, 844),
        home: const RootShell(),
        beforePump: (app) {
          app.switchToBand('b1');
          app.resetTo(Screen.gigMgr);
        },
      );

      final tabs = tester.widget<EpSegmentTabs>(
        find.byKey(const Key('band-gigs-tabs')),
      );
      expect(tabs.labels, ['My gigs', 'Discover', 'Applications']);
      expect(tabs.selected, 0);
      expect(tabs.scrollable, isFalse);
      expect(find.byType(BandMyGigsTab), findsOneWidget);
      expect(find.byType(BandDiscoverTab), findsNothing);
      expect(find.byType(BandApplicationsTab), findsNothing);
      final panel = find.byKey(
        Key(empty ? 'my-gigs-empty-next' : 'my-gigs-next-up'),
      );
      expect(panel.hitTestable(), findsOneWidget);
      final bounds = tester.getRect(panel);
      expect(
        bounds.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('band-gigs-tabs'))).bottom,
        ),
      );
      expect(
        bounds.bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(BandTabBar)).top),
      );
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(BandMyGigsTab),
                matching: find.byType(Scrollable),
              ),
            )
            .position
            .pixels,
        0,
      );
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('returning to GIGS resets DISCOVER to MY GIGS', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      home: const RootShell(),
      beforePump: (app) {
        app.switchToBand('b1');
        app.resetTo(Screen.gigMgr);
      },
    );
    await _selectTab(tester, 'DISCOVER');
    expect(find.byType(BandDiscoverTab), findsOneWidget);
    harness.app.resetTo(Screen.analytics);
    await tester.pumpAndSettle();
    expect(find.byType(GigManagerScreen), findsNothing);
    harness.app.openGigManager();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<EpSegmentTabs>(find.byKey(const Key('band-gigs-tabs')))
          .selected,
      0,
    );
    expect(find.byKey(const Key('my-gigs-next-up')), findsOneWidget);
    expect(find.byType(BandDiscoverTab), findsNothing);
    expect(find.byKey(const Key('discover-search-field')), findsNothing);
  });

  testWidgets('admin New gig pill starts gig creation', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      home: const RootShell(),
      beforePump: (app) {
        app.switchToBand('b1');
        app.resetTo(Screen.gigMgr);
      },
    );
    expect(harness.app.isAdminOf(harness.app.bandId), isTrue);
    final create = find.byKey(const Key('band-gigs-new'));
    final pill = tester.widget<EpPill>(create);
    expect(pill.label, '+ New gig');
    expect(pill.variant, EpPillVariant.outline);
    expect(pill.size, EpPillSize.chip);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gigCreate);
  });

  testWidgets('empty MY GIGS Discover affordance selects DISCOVER', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('bandBookings', <Booking>[]),
      home: const Scaffold(body: GigManagerScreen()),
      beforePump: (app) => app.switchToBand('b1'),
    );
    await tester.tap(find.byKey(const Key('my-gigs-empty-discover')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EpSegmentTabs>(find.byKey(const Key('band-gigs-tabs')))
          .selected,
      1,
    );
    expect(find.byType(BandDiscoverTab), findsOneWidget);
    expect(find.byType(BandMyGigsTab), findsNothing);
  });

  testWidgets(
    'mount refreshes applications once and leaves other loads to tabs',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = StubRepository(auth: auth)
        ..returnsStream(
          'watchMyApplications',
          () => Stream.value(<BandApplication>[]),
        );
      final applications = await repository.myApplications('b1');
      final screen = ValueNotifier<Widget>(const SizedBox.shrink());
      addTearDown(screen.dispose);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        home: Scaffold(
          body: ValueListenableBuilder<Widget>(
            valueListenable: screen,
            builder: (_, child, _) => child,
          ),
        ),
        beforePump: (app) => app.switchToBand('b1'),
      );
      expect(harness.app.myApplications, isEmpty);
      final applicationCalls = repository.callsTo('watchMyApplications');
      final browseCalls = repository.callsTo('browseOpportunities');
      final invitationCalls = repository.callsTo('invitedOpportunities');
      final bookingCalls = repository.callsTo('bandBookings');
      final projectCalls = repository.callsTo('manageGigs');
      repository.returnsStream(
        'watchMyApplications',
        () => Stream.value(applications),
      );
      screen.value = const GigManagerScreen();
      await tester.pumpAndSettle();

      expect(repository.callsTo('watchMyApplications'), applicationCalls + 1);
      expect(repository.callsTo('browseOpportunities'), browseCalls);
      expect(repository.callsTo('bandBookings'), bookingCalls + 1);
      expect(repository.callsTo('manageGigs'), projectCalls + 1);
      expect(harness.app.myApplications, applications);
      await _selectTab(tester, 'APPLICATIONS');
      expect(find.byKey(const Key('band-app-app1')), findsOneWidget);
      harness.app.say('State changed');
      await tester.pumpAndSettle();
      await _selectTab(tester, 'DISCOVER');
      expect(repository.callsTo('invitedOpportunities'), invitationCalls + 1);
      expect(
        repository.callsTo('browseOpportunities'),
        greaterThan(browseCalls),
      );
      await _selectTab(tester, 'APPLICATIONS');
      expect(repository.callsTo('watchMyApplications'), applicationCalls + 1);

      screen.value = const SizedBox.shrink();
      await tester.pumpAndSettle();
      screen.value = const GigManagerScreen();
      await tester.pumpAndSettle();
      expect(repository.callsTo('watchMyApplications'), applicationCalls + 2);
    },
  );

  testWidgets(
    'MY GIGS groups hosting, drafts, and collapsed past without list tools',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      await pumpApp(
        tester,
        auth: auth,
        repository: _ManagerRepository(auth: auth),
        home: const Scaffold(body: GigManagerScreen()),
        beforePump: (app) => app.switchToBand('b1'),
      );
      expect(find.text('GIGS'), findsOneWidget);
      final hosted = find.byKey(const Key('my-gigs-hosted-published-rsvp'));
      await _reveal(tester, hosted);
      expect(
        find.descendant(of: hosted, matching: find.text('PUBLISHED')),
        findsOneWidget,
      );
      final draft = find.byKey(const Key('my-gigs-draft-draft'));
      await _reveal(tester, draft);
      expect(
        find.descendant(
          of: draft,
          matching: find.text('finish name, date and times, venue, lineup'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('my-gigs-hosted-cancelled')), findsNothing);
      expect(find.byKey(const Key('my-gigs-past-body')), findsNothing);

      await _tapControl(tester, 'my-gigs-past-toggle');
      expect(find.textContaining('PAST ·'), findsOneWidget);
      final cancelled = find.byKey(const Key('my-gigs-hosted-cancelled'));
      await _reveal(tester, cancelled);
      expect(
        find.descendant(
          of: find.byKey(const Key('my-gigs-past-body')),
          matching: cancelled,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cancelled, matching: find.text('CANCELLED')),
        findsOneWidget,
      );
      for (final label in ['MY GIGS', 'DISCOVER', 'APPLICATIONS']) {
        await _selectTab(tester, label);
        expect(find.text('FILTERS'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                RegExp(
                  r'^(band-gigs-seg-|band-gigs-filters$|gig-actions-|gig-door-|gig-preview-|gig-edit-|gig-project-|gig-sales-|band-app-.*-booking$)',
                ).hasMatch((widget.key! as ValueKey<String>).value),
          ),
          findsNothing,
        );
      }
    },
  );

  testWidgets('hosted paid gig without sales offers Delete from MY GIGS', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await _pumpManager(
      tester,
      auth,
      _ManagerRepository(
        auth: auth,
        salesResponse: Future.value(_ManagerRepository.zeroSales),
      ),
    );
    await _tapControl(tester, 'my-gigs-hosted-published-paid');
    expect(find.byType(HostedGigScreen), findsOneWidget);
    expect(find.text('SALES · 0/50'), findsOneWidget);
    await _tapControl(tester, 'hosted-gig-actions');
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('MY GIGS opens the hosted ticket sales breakdown', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await _pumpManager(tester, auth, _ManagerRepository(auth: auth));
    await _tapControl(tester, 'my-gigs-hosted-published-paid');
    await _tapControl(tester, 'hosted-gig-actions');
    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('band-ticket-sales-sheet'));
    expect(sheet, findsOneWidget);
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
      expect(
        find.descendant(of: sheet, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('band-ticket-sales-net'))).data,
      r'$216.00',
    );
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets(
    'hosted door uses public rosters and falls back for legacy projects',
    (tester) async {
      final auth = FakeAuthService();
      final repository = _ManagerRepository(auth: auth);
      repository.projects.add(
        _project(
          id: 'legacy',
          title: 'Legacy Show',
          status: GigProjectStatus.published,
          ticketing: Ticketing.paid,
        ),
      );
      final harness = await _pumpManager(tester, auth, repository);
      for (final (projectId, gigId) in [
        ('published-external', 'not-loaded'),
        ('published-paid', 'g-paid'),
        ('legacy', null),
      ]) {
        await _tapControl(tester, 'my-gigs-hosted-$projectId');
        expect(find.byType(HostedGigScreen), findsOneWidget);
        await _tapControl(tester, 'hosted-gig-door');
        expect(find.byType(DoorModeScreen), findsOneWidget);
        expect(find.text('DOOR MODE · THE FOGHORN CLUB'), findsOneWidget);
        if (gigId == null) {
          expect(repository.projectRosterRequests, ['legacy']);
        } else {
          expect(repository.organizerRosterRequests.last, gigId);
          expect(repository.projectRosterRequests, isEmpty);
        }
        Navigator.of(tester.element(find.byType(DoorModeScreen))).pop();
        await tester.pumpAndSettle();
        harness.app.back();
        await tester.pumpAndSettle();
      }
      expect(repository.organizerRosterRequests, ['not-loaded', 'g-paid']);
    },
  );

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
}

Future<AppHarness> _pumpManager(
  WidgetTester tester,
  FakeAuthService auth,
  _ManagerRepository repository,
) async {
  await auth.signInDemo();
  return pumpApp(
    tester,
    auth: auth,
    repository: repository,
    home: const RootShell(),
    beforePump: (app) {
      app.switchToBand('b1');
      app.resetTo(Screen.gigMgr);
    },
  );
}

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('band-gigs-tabs')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder control) async {
  await tester.scrollUntilVisible(
    control,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
}

Future<void> _tapControl(WidgetTester tester, String key) async {
  final control = find.byKey(Key(key));
  await _reveal(tester, control);
  await tester.tap(control);
  await tester.pumpAndSettle();
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
