import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/screens/gig_manager.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accessibility.dart';
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
    expect(find.byKey(const Key('gig-door-published-external')), findsNothing);

    await tester.scrollUntilVisible(
      find.byType(GhostDraftRow),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byType(GhostDraftRow), findsOne);
    expect(
      find.textContaining('finish name, date and times, venue, lineup'),
      findsOne,
    );

    await tester.tap(find.byKey(const Key('band-gigs-seg-past')));
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
      expect(find.text('Riptide Release Show'), findsOne);
      expect(find.text('DOOR MODE · THE FOGHORN CLUB'), findsOne);
    },
  );

  testWidgets('manager is usable at increased text scale', (tester) async {
    await pumpApp(tester, home: scaledScreen(const GigManagerScreen()));

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
  });
}

class _ManagerRepository extends DemoRepository {
  _ManagerRepository({required super.auth});

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
  Future<DoorRoster> doorRoster(String projectId) async =>
      const DoorRoster(total: 87, checkedIn: 41, truncated: false);
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
