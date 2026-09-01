import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/screens/venue_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

void main() {
  testWidgets('submitted search tabs filter without changing a draft', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'Foghorn',
    );
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-result-tabs')), findsOne);
    // The event matches through its Foghorn Diet lineup relationship.
    expect(find.text('RIPTIDE RELEASE SHOW'), findsWidgets);
    expect(find.text('FOGHORN DIET'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'unsubmitted draft',
    );
    await tester.tap(find.byKey(const Key('explore-tab-bands')));
    await tester.pump();

    expect(harness.app.query, 'Foghorn');
    expect(harness.app.exploreResultType, ExploreResultType.bands);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('explore-search-field')))
          .controller!
          .text,
      'unsubmitted draft',
    );
    expect(find.text('EVENTS'), findsNothing);
    expect(find.text('FOGHORN DIET'), findsOne);

    await tester.tap(find.byKey(const Key('explore-tab-venues')));
    await tester.pump();
    expect(find.text('THE FOGHORN CLUB'), findsOne);
    expect(find.text('FOGHORN DIET'), findsNothing);

    await tester.tap(find.byKey(const Key('explore-search-clear')));
    await tester.pumpAndSettle();
    expect(harness.app.query, isEmpty);
    expect(find.text('GENRES'), findsNothing);
    expect(find.byKey(const Key('explore-filter-button')), findsOne);
  });

  testWidgets('venue search rows navigate without replacing the query', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    harness.app.setQuery('Foghorn Club');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('explore-tab-venues')));
    await tester.pump();
    await tester.tap(find.text('THE FOGHORN CLUB'));
    await tester.pump();

    expect(harness.app.current.screen, Screen.venue);
    expect(harness.app.current.param, 'v1');
    expect(harness.app.query, 'Foghorn Club');
  });

  testWidgets('expanded band directory loads and deduplicates another page', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _PagedBandsRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: ExploreScreen()),
    );

    final toggle = find.byKey(const Key('explore-toggle-bands'));
    await tester.scrollUntilVisible(
      toggle,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore-bands-load-more')), findsOne);

    await tester.tap(find.byKey(const Key('explore-bands-load-more')));
    await tester.pumpAndSettle();
    expect(repository.bandCalls, 2);
    expect(find.text('PIGEON COURT', skipOffstage: false), findsOne);
    expect(find.text('MISSION CREEP', skipOffstage: false), findsOne);
    expect(find.byKey(const Key('explore-bands-end')), findsOne);
  });

  testWidgets('venue detail shows map, chronological events, and performers', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
    );

    expect(find.text('THE FOGHORN CLUB'), findsOne);
    expect(find.byKey(const Key('venue-detail-distance')), findsOne);
    expect(find.text('UPCOMING EVENTS'), findsOne);
    final cards = tester
        .widgetList<FanEventCard>(find.byType(FanEventCard))
        .toList();
    expect(cards, isNotEmpty);
    final startsAt = cards.map((card) => card.gig.startsAt).toList();
    expect(startsAt, orderedEquals([...startsAt]..sort()));

    final firstGig = cards.first.gig;
    await tester.tap(find.byKey(ValueKey('fan-event-${firstGig.id}')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, firstGig.id);
    harness.app.back();
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('venue-detail-content')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(find.text('PERFORMING BANDS'), findsOne);
    expect(find.byKey(const ValueKey('venue-band-b1')), findsOne);
    await tester.tap(find.byKey(const ValueKey('venue-band-b1')));
    expect(harness.app.current.screen, Screen.band);
    expect(harness.app.current.param, 'b1');
  });

  testWidgets('venue detail retries a failed relationship load', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _RetryVenueRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
    );

    expect(find.text("COULDN'T LOAD THIS VENUE"), findsOne);
    await tester.tap(find.byKey(const Key('venue-detail-retry')));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('THE FOGHORN CLUB'), findsOne);
  });

  testWidgets('venue detail has a distinct missing state', (tester) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: VenueDetailScreen(venueId: 'missing')),
    );
    expect(find.text('VENUE NOT FOUND'), findsOne);
  });

  testWidgets('venue detail has a quiet no-events state', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _EmptyVenueRepository(auth: auth),
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
    );
    expect(find.text('Nothing on the calendar right now.'), findsOne);
    expect(find.text('No performers announced yet.'), findsOne);
  });

  testWidgets('fan card exposes metadata and auth-gates save', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final gig = DemoData.gigs.first;
    final harness = await pumpApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(gig: gig, app: context.read<AppState>()),
          ),
        ),
      ),
    );

    expect(find.text(gig.title.toUpperCase()), findsWidgets);
    expect(find.text('FREE'), findsOne);
    expect(find.text('18+'), findsOne);
    expect(find.textContaining('DOORS 8PM'), findsOne);
    expect(
      find.text('Mission Creep · Dial Tone Grief · Static Bloom'),
      findsOne,
    );

    await tester.tap(find.byKey(ValueKey('share-${gig.id}')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Link copied'), findsOne);

    await tester.tap(find.byKey(ValueKey('save-${gig.id}')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.auth);
    expect(harness.app.pending?.kind, PendingKind.save);
    expect(harness.app.pending?.id, gig.id);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('fan card RSVP changes to the going state', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final gig = DemoData.gigs.first;
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: Consumer<AppState>(
        builder: (context, app, _) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(gig: gig, app: app),
          ),
        ),
      ),
    );

    expect(find.text('RSVP'), findsOne);
    await tester.tap(find.byKey(ValueKey('ticket-action-${gig.id}')));
    await tester.pump();
    expect(harness.app.rsvps, contains(gig.id));
    expect(find.text('GOING ✓'), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('gig detail exposes age and an auth-gated save action', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g4')),
    );

    expect(find.text('AGE'), findsOne);
    expect(find.text('21+'), findsOne);
    await tester.tap(find.byKey(const ValueKey('gig-detail-save-g4')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.auth);
    expect(harness.app.pending?.kind, PendingKind.save);
    expect(harness.app.pending?.id, 'g4');
  });

  testWidgets('external ticket records are not treated as active RSVPs', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _ExternalRsvpRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );

    expect(harness.app.rsvps, contains('g4'));
    expect(harness.app.upcomingRsvpGigs, isEmpty);
    expect(find.byKey(const ValueKey('fan-event-g4')), findsNothing);
    expect(find.byKey(const ValueKey('next-show-g4')), findsNothing);
    expect(find.byTooltip('Show QR code'), findsNothing);
    expect(find.byKey(const ValueKey('show-qr-g4')), findsNothing);
  });
}

class _RetryVenueRepository extends DemoRepository {
  _RetryVenueRepository({required super.auth});

  int calls = 0;

  @override
  Future<VenueDetail?> venueDetail(String venueId) {
    calls++;
    if (calls == 1) throw Exception('venue failed');
    return super.venueDetail(venueId);
  }
}

class _ExternalRsvpRepository extends DemoRepository {
  _ExternalRsvpRepository({required super.auth});

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: [
        for (final gig in DemoData.gigs)
          if (gig.id != 'g4') gig,
      ],
      venues: DemoData.venues,
      bands: DemoData.bands,
    ),
  );

  @override
  Stream<Interactions> myInteractions() => Stream.value(
    Interactions(
      rsvpGigIds: {'g4'},
      followBandIds: {},
      savedGigIds: {},
      gigs: [DemoData.gigs.firstWhere((gig) => gig.id == 'g4')],
      attendedCount: 0,
    ),
  );
}

class _PagedBandsRepository extends DemoRepository {
  _PagedBandsRepository({required super.auth});

  int bandCalls = 0;

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async {
    bandCalls++;
    if (cursor == null) {
      return BandPage(
        items: [DemoData.bands['b1']!, DemoData.bands['b2']!],
        continueCursor: 'next',
        isDone: false,
      );
    }
    return BandPage(
      items: [DemoData.bands['b2']!, DemoData.bands['b3']!],
      continueCursor: null,
      isDone: true,
    );
  }
}

class _EmptyVenueRepository extends DemoRepository {
  _EmptyVenueRepository({required super.auth});

  @override
  Future<VenueDetail?> venueDetail(String venueId) async => VenueDetail(
    venue: DemoData.venues['v1']!,
    gigs: const [],
    bands: const {},
    truncated: false,
  );
}
