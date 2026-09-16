import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/door_mode.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_my_gigs_tab.dart';
import 'package:earplug/widgets/band_next_up_card.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('upcoming lists every booking in order and opens artist detail', (
    tester,
  ) async {
    final harness = await _pumpTab(
      tester,
      bookings: [_booking('later', days: 6), _booking('first', days: 2)],
    );
    final first = find.byKey(const Key('band-booking-first'));
    final later = find.byKey(const Key('band-booking-later'));

    expect(find.text('UPCOMING · 2'), findsOneWidget);
    expect(find.byKey(const Key('my-gigs-empty-next')), findsNothing);
    expect(
      find.descendant(of: first, matching: find.text('FIRST SHOW')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('THE FOGHORN CLUB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('BOOKED')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: later, matching: find.text('BOOKED')),
      findsOneWidget,
    );
    expect(
      tester.getRect(first).bottom,
      lessThanOrEqualTo(tester.getRect(later).top),
    );
    await _tapRow(tester, 'band-booking-first');

    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, 'first');
    expect(
      (harness.app.repository as _MyGigsRepository).lastBookingSide,
      BookingSide.artist,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('hosting rows show published state and open hosted details', (
    tester,
  ) async {
    final harness = await _pumpTab(
      tester,
      projects: [_project('published-rsvp')],
    );
    final row = find.byKey(const Key('my-gigs-hosted-published-rsvp'));

    expect(find.text('HOSTING · 1'), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('PUBLISHED')),
      findsOneWidget,
    );
    expect(find.text('DOOR'), findsNothing);
    expect(find.text('PREVIEW'), findsNothing);
    expect(find.text('EDIT'), findsNothing);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    await _tapRow(tester, 'my-gigs-hosted-published-rsvp');

    expect(harness.app.current.screen, Screen.hostedGig);
    expect(harness.app.current.param, 'published-rsvp');
  });

  testWidgets('unpublished hosting changes use the warning pill', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      projects: [_project('published-paid', unpublishedChanges: true)],
    );
    final row = find.byKey(const Key('my-gigs-hosted-published-paid'));
    final status = tester.widget<StatusPill>(
      find.descendant(of: row, matching: find.byType(StatusPill)),
    );

    expect(status.label, 'UNPUBLISHED CHANGES');
    expect(status.tone, EpStatusPillTone.warning);
    expect(tester.takeException(), isNull);
  });

  for (final member in [false, true]) {
    testWidgets(
      member
          ? 'draft is inert for a non-admin member'
          : 'admin draft opens the gig editor',
      (tester) async {
        final harness = await _pumpTab(
          tester,
          projects: [
            _project('draft', status: GigProjectStatus.draft, incomplete: true),
          ],
          member: member,
        );
        final row = find.byKey(const Key('my-gigs-draft-draft'));
        final original = harness.app.current;

        expect(harness.app.isAdminOf('b1'), !member);
        expect(find.text('DRAFTS · 1'), findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text('UNTITLED DRAFT')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: row,
            matching: find.text('finish name, date and times, venue, lineup'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('DRAFT')),
          findsOneWidget,
        );

        if (member) {
          expect(tester.widget<EpEntityRow>(row).onTap, isNull);
          expect(
            find.descendant(
              of: row,
              matching: find.byIcon(Icons.chevron_right),
            ),
            findsNothing,
          );
        }
        await _tapRow(tester, 'my-gigs-draft-draft');

        if (member) {
          expect(harness.app.current, original);
          expect(harness.app.gfProject, isNull);
        } else {
          expect(harness.app.current.screen, Screen.gigCreate);
          expect(harness.app.gfProject?.id, 'draft');
        }
      },
    );
  }

  testWidgets('complete drafts retain the review-before-publishing hint', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      projects: [_project('ready-draft', status: GigProjectStatus.draft)],
    );

    expect(find.text('review before publishing'), findsOneWidget);
  });

  testWidgets('past is collapsed, counts cancellations, and opens history', (
    tester,
  ) async {
    final harness = await _pumpTab(
      tester,
      bookings: [
        _booking('past', days: -2),
        _booking('cancelled-booking', status: BookingStatus.refunded, days: 3),
      ],
      projects: [_project('cancelled', status: GigProjectStatus.cancelled)],
    );

    expect(find.text('PAST · 3'), findsOneWidget);
    expect(find.text('Incl. 2 cancelled'), findsOneWidget);
    expect(find.byKey(const Key('my-gigs-past-body')), findsNothing);
    expect(find.byKey(const Key('band-booking-past')), findsNothing);
    await _tapRow(tester, 'my-gigs-past-toggle');

    expect(find.byKey(const Key('my-gigs-past-body')), findsOneWidget);
    final pastBooking = find.byKey(const Key('band-booking-past'));
    final cancelledProject = find.byKey(const Key('my-gigs-hosted-cancelled'));
    final cancelledBooking = find.byKey(
      const Key('band-booking-cancelled-booking'),
    );
    expect(
      find.descendant(of: pastBooking, matching: find.text('DONE')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cancelledProject, matching: find.text('CANCELLED')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cancelledBooking, matching: find.text('CANCELLED')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    await _tapRow(tester, 'band-booking-past');
    expect(harness.app.current.screen, Screen.bookingDetail);
    expect(harness.app.current.param, 'past');
    await _tapRow(tester, 'my-gigs-hosted-cancelled');
    expect(harness.app.current.screen, Screen.hostedGig);
    expect(harness.app.current.param, 'cancelled');
    await _tapRow(tester, 'my-gigs-past-toggle');
    expect(find.byKey(const Key('my-gigs-past-body')), findsNothing);
  });

  testWidgets('empty panel discovers when nothing is booked or hosted', (
    tester,
  ) async {
    var discoveries = 0;
    await _pumpTab(tester, onDiscover: () => discoveries++);

    expect(find.byKey(const Key('my-gigs-empty-next')), findsOneWidget);
    expect(
      find.text('No gigs coming up — find your next stage'),
      findsOneWidget,
    );
    expect(find.textContaining('UPCOMING'), findsNothing);
    expect(find.text('PAST · 0'), findsOneWidget);
    expect(find.textContaining('Incl.'), findsNothing);
    await tester.tap(find.byKey(const Key('my-gigs-empty-discover')));
    expect(discoveries, 1);
  });

  testWidgets('a hosted gig without bookings hides the empty panel', (
    tester,
  ) async {
    await _pumpTab(tester, projects: [_project('published-rsvp')]);

    expect(find.byKey(const Key('my-gigs-empty-next')), findsNothing);
    expect(find.byKey(const Key('my-gigs-empty-discover')), findsNothing);
    expect(find.textContaining('UPCOMING'), findsNothing);
    expect(find.text('HOSTING · 1'), findsOneWidget);
    expect(
      tester.getRect(find.text('HOSTING · 1')).top,
      closeTo(
        tester.getRect(find.byKey(const Key('band-next-up'))).bottom + 16,
        0.01,
      ),
    );
  });

  testWidgets('up-next hero leads the list and is visible at 390x844', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      size: const Size(390, 844),
      bookings: [_booking('first', days: 1), _booking('later', days: 3)],
      projects: [_project('published-paid', unpublishedChanges: true)],
    );
    final hero = tester.getRect(find.byKey(const Key('band-next-up')));
    final upcoming = find.text('UPCOMING · 2');

    expect(
      tester.widget<ListView>(find.byType(ListView)).childrenDelegate,
      isA<SliverChildListDelegate>().having(
        (delegate) => delegate.children.first,
        'first child',
        isA<BandNextUpCard>(),
      ),
    );
    expect(find.text('UP NEXT').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('band-next-door-mode')).hitTestable(),
      findsOneWidget,
    );
    expect(hero.top, greaterThanOrEqualTo(0));
    expect(hero.bottom, lessThan(844));
    expect(tester.getRect(upcoming).top, closeTo(hero.bottom + 16, 0.01));
    expect(upcoming.hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('my-gigs-empty-next')), findsNothing);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      0,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('up-next hero shows the next published gig and opens door mode', (
    tester,
  ) async {
    final harness = await _pumpTab(tester);
    final hero = find.byKey(const Key('band-next-up'));

    expect(hero, findsOneWidget);
    expect(find.byKey(const Key('band-next-up-empty')), findsNothing);
    expect(
      find.descendant(of: hero, matching: find.text('RIPTIDE RELEASE SHOW')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<EpMonoText>(find.byKey(const Key('band-next-up-when')))
          .text,
      endsWith(' · Doors 8PM'),
    );
    final details = tester.widgetList<EpMonoText>(
      find.descendant(of: hero, matching: find.byType(EpMonoText)),
    );
    expect(
      details.any(
        (text) =>
            text.text.startsWith('The Foghorn Club · ') &&
            text.text.endsWith(' RSVPs · counting live'),
      ),
      isTrue,
    );
    expect(find.byKey(const Key('band-next-public-gig')), findsOneWidget);

    await tester.tap(find.byKey(const Key('band-next-door-mode')));
    await tester.pumpAndSettle();

    expect(find.byType(DoorModeScreen), findsOneWidget);
    expect(
      (harness.app.repository as _MyGigsRepository).organizerRosterRequests,
      ['g2'],
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('door-organizer-roster'))).data,
      'RSVPs 4/17 · Tickets 3/12',
    );
  });

  testWidgets('up-next hero opens the public gig', (tester) async {
    final harness = await _pumpTab(tester);

    await tester.tap(find.byKey(const Key('band-next-public-gig')));
    await tester.pump();

    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, 'g2');
  });

  testWidgets('members get no door mode on the up-next hero', (tester) async {
    await _pumpTab(tester, member: true);

    expect(find.byKey(const Key('band-next-up')), findsOneWidget);
    expect(find.byKey(const Key('band-next-door-mode')), findsNothing);
    expect(find.byKey(const Key('band-next-public-gig')), findsOneWidget);
  });

  testWidgets('empty up-next hero prompts admins to publish a gig', (
    tester,
  ) async {
    final harness = await _pumpTab(tester, configure: _withoutPublishedGigs);

    expect(find.byKey(const Key('band-next-up')), findsNothing);
    expect(find.byKey(const Key('band-next-up-empty')), findsOneWidget);
    expect(find.text('NOTHING SCHEDULED'), findsOneWidget);
    expect(find.text('NO GIG COMING UP — PUBLISH ONE'), findsOneWidget);
    await tester.tap(find.byKey(const Key('band-next-up-publish')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.gigCreate);
  });

  testWidgets('empty up-next hero offers members no publish action', (
    tester,
  ) async {
    await _pumpTab(tester, member: true, configure: _withoutPublishedGigs);

    expect(find.byKey(const Key('band-next-up-empty')), findsOneWidget);
    expect(find.byKey(const Key('band-next-up-publish')), findsNothing);
  });

  for (final state in [
    null,
    StripeAccountState.none,
    StripeAccountState.onboarding,
    StripeAccountState.restricted,
    StripeAccountState.enabled,
  ]) {
    testWidgets('payouts row flags unfinished Stripe setup for $state', (
      tester,
    ) async {
      final harness = await _pumpTab(
        tester,
        configure: (repository) => _withPayoutState(repository, state),
      );
      expect(harness.app.bandPayoutStatus?.state, state);

      final row = find.byKey(const Key('band-dash-payouts'));
      await tester.scrollUntilVisible(
        row,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MANAGE'), findsOneWidget);
      final badge = find.descendant(
        of: row,
        matching: find.byKey(const Key('band-dash-payouts-badge')),
      );
      if (state == StripeAccountState.enabled) {
        expect(badge, findsNothing);
        expect(find.text('SET UP'), findsNothing);
      } else {
        expect(badge, findsOneWidget);
        expect(
          find.descendant(of: badge, matching: find.text('SET UP')),
          findsOneWidget,
        );
      }

      await tester.ensureVisible(row);
      await tester.pump();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(harness.app.current.screen, Screen.bandPayouts);
    });
  }

  testWidgets('members see no payouts row', (tester) async {
    await _pumpTab(
      tester,
      configure: (repository) =>
          _withPayoutState(repository, StripeAccountState.none),
      member: true,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('PAST · 0'), findsOneWidget);
    expect(find.text('MANAGE'), findsNothing);
    expect(find.byKey(const Key('band-dash-payouts')), findsNothing);
  });

  for (final source in ['bandBookings', 'manageGigs']) {
    testWidgets('empty loading state waits for $source', (tester) async {
      late Completer<void> gate;
      await _pumpTab(
        tester,
        configure: (repository) => gate = repository.gate(source),
      );

      expect(find.text('LOADING…'), findsOneWidget);
      expect(find.byKey(const Key('my-gigs-empty-next')), findsNothing);
      expect(find.byKey(const Key('my-gigs-past-toggle')), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('LOADING…'), findsNothing);
      expect(find.byKey(const Key('my-gigs-empty-next')), findsOneWidget);
    });
  }

  testWidgets('pull to refresh reloads both bookings and managed gigs', (
    tester,
  ) async {
    final harness = await _pumpTab(tester);
    final repository = harness.app.repository as _MyGigsRepository;
    final bookingCalls = repository.callsTo('bandBookings');
    final projectCalls = repository.callsTo('manageGigs');
    expect(bookingCalls, greaterThan(0));
    expect(projectCalls, greaterThan(0));
    repository
      ..returns('bandBookings', [_booking('refreshed', days: 1)])
      ..returns('manageGigs', [_project('refreshed-project')]);

    await tester.drag(find.byType(ListView), const Offset(0, 450));
    await tester.pumpAndSettle();

    expect(repository.callsTo('bandBookings'), greaterThan(bookingCalls));
    expect(repository.callsTo('manageGigs'), greaterThan(projectCalls));
    expect(find.byKey(const Key('band-booking-refreshed')), findsOneWidget);
    expect(
      find.byKey(const Key('my-gigs-hosted-refreshed-project')),
      findsOneWidget,
    );
  });
}

Future<AppHarness> _pumpTab(
  WidgetTester tester, {
  List<Booking> bookings = const [],
  List<GigProject> projects = const [],
  bool member = false,
  VoidCallback? onDiscover,
  Size size = const Size(402, 900),
  void Function(_MyGigsRepository)? configure,
}) async {
  final auth = FakeAuthService();
  await auth.signInDemo();
  final repository = _MyGigsRepository(
    auth: auth,
    bookings: bookings,
    projects: projects,
    member: member,
  );
  configure?.call(repository);
  return pumpApp(
    tester,
    auth: auth,
    repository: repository,
    size: size,
    home: Scaffold(body: BandMyGigsTab(onDiscover: onDiscover ?? () {})),
    beforePump: (app) {
      app.switchToBand('b1');
      app.resetTo(Screen.gigMgr);
    },
  );
}

Future<void> _tapRow(WidgetTester tester, String key) async {
  final row = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    row,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

class _MyGigsRepository extends StubRepository {
  _MyGigsRepository({
    required super.auth,
    required this.bookings,
    required this.projects,
    required bool member,
  }) {
    returns('bandBookings', bookings);
    returns('manageGigs', projects);
    final band = bandFixture(id: 'b1', name: 'Foghorn Diet');
    returns('band', band);
    returnsStream(
      'myBands',
      () => Stream.value([
        BandMembership(band: band, role: member ? 'member' : 'admin'),
      ]),
    );
  }

  final List<Booking> bookings;
  final List<GigProject> projects;
  final organizerRosterRequests = <String>[];
  BookingSide? lastBookingSide;

  @override
  Future<Booking?> booking(String bookingId, {BookingSide? viewAs}) async {
    lastBookingSide = viewAs;
    return bookings.where((booking) => booking.id == bookingId).firstOrNull;
  }

  @override
  Future<DoorCounts> organizerDoorRoster(String gigId) async {
    organizerRosterRequests.add(gigId);
    return const DoorCounts(
      rsvpTotal: 17,
      rsvpCheckedIn: 4,
      ticketsSold: 12,
      ticketsCheckedIn: 3,
      truncated: false,
    );
  }

  @override
  Future<GigProject> getGigProject(String projectId) async =>
      projects.firstWhere((project) => project.id == projectId);
}

/// The band has no published gigs, so the up-next hero shows its empty state.
void _withoutPublishedGigs(_MyGigsRepository repository) =>
    repository.returnsStream(
      'feed',
      () => Stream.value(const FeedSnapshot(gigs: [], venues: {}, bands: {})),
    );

/// A `null` state stands for a failed status load.
void _withPayoutState(_MyGigsRepository repository, StripeAccountState? state) {
  if (state == null) {
    repository.wraps<StripeAccountStatus>(
      'bandPayoutStatus',
      (_) => throw StateError('offline'),
    );
    return;
  }
  repository.returns(
    'bandPayoutStatus',
    StripeAccountStatus(
      state: state,
      hasAccount: state != StripeAccountState.none,
      chargesEnabled: state == StripeAccountState.enabled,
      payoutsEnabled: state == StripeAccountState.enabled,
      detailsSubmitted: state == StripeAccountState.enabled,
      requirementsDue: const [],
      cardPaymentsStatus: state == StripeAccountState.enabled ? 'active' : null,
    ),
  );
}

Booking _booking(
  String id, {
  required int days,
  BookingStatus status = BookingStatus.confirmed,
}) => Booking(
  id: id,
  opportunityId: 'opp1',
  opportunityTitle: '$id show',
  opportunitySlug: '$id-show',
  slotId: 'opp1-headliner',
  slotRole: SlotRole.headliner,
  slotRequired: true,
  organizationId: 'org1',
  organizationName: 'The Foghorn Club',
  bandId: 'b1',
  bandName: 'Foghorn Diet',
  bandSlug: 'foghorn-diet',
  applicationId: 'app-$id',
  status: status,
  revision: 3,
  startsAt: DateTime.now().add(Duration(days: days)),
  fee: const FeeBreakdown(
    grossMinor: 10000,
    commissionBps: 1000,
    commissionMinor: 1000,
    artistNetMinor: 9000,
    currency: 'usd',
  ),
  cancellationTemplate: CancellationTemplate.standard,
  organizerAcceptedTermsAt: DateTime.now(),
  viewerSide: BookingSide.artist,
  venue: const BookingVenue(
    id: 'v1',
    name: 'The Foghorn Club',
    approxLabel: 'Oakland',
  ),
);

GigProject _project(
  String id, {
  GigProjectStatus status = GigProjectStatus.published,
  bool unpublishedChanges = false,
  bool incomplete = false,
}) {
  final startsAt = DateTime.now().add(const Duration(days: 2));
  return GigProject(
    id: id,
    bandId: 'b1',
    publicGigId: status == GigProjectStatus.published ? 'g2' : null,
    status: status,
    revision: unpublishedChanges ? 3 : 2,
    publishedRevision: status == GigProjectStatus.published ? 2 : null,
    title: incomplete ? null : '$id show',
    doorsAt: incomplete ? null : startsAt.subtract(const Duration(hours: 1)),
    startsAt: incomplete ? null : startsAt,
    venueId: incomplete ? null : 'v1',
    price: 0,
    flyKey: 'blue',
    overlay: true,
    desc: '',
    ticketing: id == 'published-paid' ? Ticketing.paid : Ticketing.rsvp,
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
