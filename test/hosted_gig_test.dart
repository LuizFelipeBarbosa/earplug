import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/screens/hosted_gig.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/gig_project_actions.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('published RSVP detail opens door, editor, and draft preview', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _HostedGigRepository(auth: auth);
    final harness = await _pumpHostedGig(tester, repository, auth);
    final app = harness.app;

    expect(find.byType(HostedGigScreen), findsOne);
    expect(find.text('RIPTIDE RELEASE SHOW'), findsOne);
    final status = tester.widget<StatusPill>(
      find.byKey(const Key('hosted-gig-status')),
    );
    expect(status.label, 'PUBLISHED');
    expect(status.tone, EpStatusPillTone.success);
    expect(find.text('DOOR'), findsOne);
    expect(find.text('PREVIEW'), findsOne);
    expect(find.text('EDIT'), findsOne);
    expect(find.text('Free · RSVP'), findsOne);
    expect(find.text('GOING · ${app.rsvpCount(app.gig('g2')!)}'), findsOne);
    expect(app.identity, isA<BandIdentity>());
    expect((app.identity as BandIdentity).bandId, 'b1');
    expect(find.byType(BandTabBar), findsOne);
    expect(find.byType(FanTabBar), findsNothing);

    await _tapControl(tester, 'hosted-gig-door');
    expect(find.byType(DoorModeScreen), findsOne);
    expect(find.text('DOOR MODE · THE FOGHORN CLUB'), findsOne);
    expect(repository.organizerRosterRequests, ['g2']);
    expect(repository.projectRosterRequests, isEmpty);
    Navigator.of(tester.element(find.byType(DoorModeScreen))).pop();
    await tester.pumpAndSettle();

    await _tapControl(tester, 'hosted-gig-edit');
    expect(app.current.screen, Screen.gigCreate);
    expect(app.gfProject?.id, 'published-rsvp');
    app.back();
    await tester.pumpAndSettle();

    await _tapControl(tester, 'hosted-gig-preview');
    expect(app.current.screen, Screen.gigCreate);
    expect(find.byKey(const Key('redesigned-gig-draft-preview')), findsOne);
  });

  testWidgets('overflow preserves lifecycle actions and cancellation copy', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await _pumpHostedGig(tester, _HostedGigRepository(auth: auth), auth);

    await _tapControl(tester, 'hosted-gig-actions');
    expect(find.byType(EpActionSheet), findsOne);
    final destructive = tester
        .element(find.byType(EpActionSheet))
        .epColors
        .destructive;
    for (final label in ['Duplicate', 'Unpublish…', 'Cancel gig…', 'Delete']) {
      expect(find.text(label), findsOne);
      expect(
        tester.widget<Text>(find.text(label)).style?.color,
        label == 'Delete' ? destructive : isNot(destructive),
      );
    }

    await tester.tap(find.text('Cancel gig…'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel gig?'), findsOne);
    expect(
      find.text(
        'The gig leaves discovery but its public page stays available as cancelled.',
      ),
      findsOne,
    );
    expect(find.text('KEEP'), findsOne);
    expect(find.text('CONFIRM'), findsOne);
    await tester.tap(find.text('KEEP'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel gig?'), findsNothing);
    expect(find.text('PUBLISHED'), findsOne);
  });

  testWidgets('paid sales load once, hide Delete, and open the sales sheet', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final response = Completer<TicketSales>();
    final repository = _HostedGigRepository(
      auth: auth,
      salesResponse: response.future,
    );
    final harness = await _pumpHostedGig(
      tester,
      repository,
      auth,
      projectId: 'published-paid',
    );
    expect(find.byKey(const Key('hosted-gig-sales')), findsNothing);
    expect(repository.salesRequests, ['g-paid']);
    await harness.app.refreshManagedGigs();
    await tester.pumpAndSettle();
    expect(repository.salesRequests, ['g-paid']);

    response.complete(_HostedGigRepository.paidSales);
    await tester.pumpAndSettle();
    expect(
      tester.widget<EpMonoText>(find.byKey(const Key('hosted-gig-sales'))).text,
      'SALES · 12/50',
    );
    expect(find.text(r'Paid $20.00'), findsOne);
    await _tapControl(tester, 'hosted-gig-actions');
    expect(find.text('Sales'), findsOne);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('band-ticket-sales-sheet')), findsOne);
    expect(find.text('12/50'), findsOne);
    expect(repository.salesRequests, ['g-paid']);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await _tapControl(tester, 'hosted-gig-actions');
    await tester.tap(find.text('Cancel gig…'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel gig?'), findsOne);
    expect(
      find.text(
        'Sold tickets are refunded in full and buyers are emailed. The gig leaves discovery but its public page stays available as cancelled.',
      ),
      findsOne,
    );
  });

  testWidgets('non-admin members have no management actions', (tester) async {
    final auth = FakeAuthService();
    final harness = await _pumpHostedGig(
      tester,
      _HostedGigRepository(auth: auth, member: true),
      auth,
    );
    expect(harness.app.isAdminOf('b1'), isFalse);
    expect(find.text('RIPTIDE RELEASE SHOW'), findsOne);
    expect(find.byKey(const Key('hosted-gig-actions')), findsNothing);
    expect(find.byKey(const Key('hosted-gig-edit')), findsNothing);
    expect(find.byKey(const Key('hosted-gig-door')), findsNothing);
    expect(find.byKey(const Key('hosted-gig-preview')), findsOne);
  });

  testWidgets('cancelled detail is read-only', (tester) async {
    final auth = FakeAuthService();
    await _pumpHostedGig(
      tester,
      _HostedGigRepository(auth: auth),
      auth,
      projectId: 'cancelled',
    );
    final status = tester.widget<StatusPill>(
      find.byKey(const Key('hosted-gig-status')),
    );
    expect(status.label, 'CANCELLED');
    expect(status.tone, EpStatusPillTone.neutral);
    expect(find.text('TOOLS'), findsNothing);
    for (final action in ['door', 'preview', 'edit', 'actions']) {
      expect(find.byKey(Key('hosted-gig-$action')), findsNothing);
    }
  });

  testWidgets('missing project can return to the previous screen', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await _pumpHostedGig(
      tester,
      _HostedGigRepository(auth: auth),
      auth,
      projectId: 'unknown',
    );
    expect(find.text('GIG UNAVAILABLE'), findsOne);
    await _tapControl(tester, 'hosted-gig-unavailable-back');
    expect(harness.app.current.screen, Screen.gigMgr);
    expect(find.byType(HostedGigScreen), findsNothing);
  });

  testWidgets('drafts handle missing details without door access', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _HostedGigRepository(auth: auth);
    final harness = await _pumpHostedGig(
      tester,
      repository,
      auth,
      projectId: 'draft',
    );
    expect(find.text('UNTITLED GIG'), findsOne);
    expect(find.text('DRAFT'), findsOne);
    expect(find.text('Venue TBD'), findsOne);
    expect(find.byKey(const Key('hosted-gig-door')), findsNothing);
    expect(find.byKey(const Key('hosted-gig-preview')), findsOne);
    expect(find.byKey(const Key('hosted-gig-edit')), findsOne);
    expect(doorLaunchFor(harness.app, repository.projects[3]), isNull);
    await _tapControl(tester, 'hosted-gig-back-control');
    expect(harness.app.current.screen, Screen.gigMgr);
  });

  testWidgets('unpublished changes use the warning status', (tester) async {
    final auth = FakeAuthService();
    final repository = _HostedGigRepository(auth: auth);
    repository.projects[0] = repository.projects[0].copyWith(revision: 3);
    await _pumpHostedGig(tester, repository, auth);
    final status = tester.widget<StatusPill>(
      find.byKey(const Key('hosted-gig-status')),
    );
    expect(status.label, 'UNPUBLISHED CHANGES');
    expect(status.tone, EpStatusPillTone.warning);
  });

  testWidgets('390-wide phone lays out all tools without overflow', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await _pumpHostedGig(
      tester,
      _HostedGigRepository(auth: auth),
      auth,
      projectId: 'published-paid',
      size: const Size(390, 844),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('hosted-gig-edit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final edit = tester.getRect(find.byKey(const Key('hosted-gig-edit')));
    expect(edit.left, greaterThanOrEqualTo(0));
    expect(edit.right, lessThanOrEqualTo(390));
    expect(
      edit.bottom,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(BandTabBar)).dy),
    );
  });

  test('management paths do not resolve as fan gigs or band slugs', () {
    for (final path in ['/manage', '/manage/gigs/published-rsvp']) {
      final uri = Uri.parse('https://earplug.app$path');
      expect(bandSlugFromUri(uri), isNull);
      expect(gigIdFromUri(uri), isNull);
    }
  });
}

Future<AppHarness> _pumpHostedGig(
  WidgetTester tester,
  _HostedGigRepository repository,
  FakeAuthService auth, {
  String projectId = 'published-rsvp',
  Size size = const Size(402, 900),
}) async {
  await auth.signInDemo();
  final harness = await pumpApp(
    tester,
    auth: auth,
    repository: repository,
    size: size,
    home: const RootShell(),
  );
  harness.app.switchToBand('b1');
  harness.app.openHostedGig(projectId);
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _tapControl(WidgetTester tester, String key) async {
  final control = find.byKey(Key(key));
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

class _HostedGigRepository extends DemoRepository {
  _HostedGigRepository({
    required super.auth,
    this.salesResponse,
    this.member = false,
  });

  final bool member;

  @override
  Stream<List<BandMembership>> myBands() => member
      ? Stream.value([
          BandMembership(band: DemoData.bands['b1']!, role: 'member'),
        ])
      : super.myBands();

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
    price: ticketing == Ticketing.paid ? 20 : 0,
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
