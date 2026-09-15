import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/screens/venue_detail.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets('submitted search stays while an unsubmitted draft is typed', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    harness.app.go(Screen.explore);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'Foghorn',
    );
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();

    // The event matches through its Foghorn Diet lineup relationship.
    expect(find.text('RIPTIDE RELEASE SHOW'), findsWidgets);
    await _scrollResultsTo(tester, find.text('FOGHORN DIET'));
    expect(find.text('FOGHORN DIET'), findsWidgets);
    await _scrollResultsTo(tester, find.text('THE FOGHORN CLUB'));
    expect(find.text('THE FOGHORN CLUB'), findsWidgets);

    await _scrollToTop(tester);
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'unsubmitted draft',
    );
    expect(harness.app.query, 'Foghorn');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('explore-search-field')))
          .controller!
          .text,
      'unsubmitted draft',
    );
    expect(find.text('RIPTIDE RELEASE SHOW'), findsWidgets);
    await _scrollResultsTo(tester, find.text('FOGHORN DIET'));
    expect(find.text('FOGHORN DIET'), findsWidgets);
    await _scrollResultsTo(tester, find.text('THE FOGHORN CLUB'));
    expect(find.text('THE FOGHORN CLUB'), findsWidgets);

    await _scrollToTop(tester);
    await tester.tap(find.byKey(const Key('explore-search-clear')));
    await tester.pumpAndSettle();
    expect(harness.app.query, isEmpty);
    expect(find.byKey(const ValueKey('explore-browse-all')), findsOne);
  });

  testWidgets('venue search rows navigate without replacing the query', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    harness.app.go(Screen.explore);
    await tester.pumpAndSettle();
    harness.app.setQuery('Foghorn Club');
    await tester.pumpAndSettle();
    await tester.tap(find.text('THE FOGHORN CLUB'));
    await tester.pump();

    expect(harness.app.current.screen, Screen.venue);
    expect(harness.app.current.param, 'v1');
    expect(harness.app.query, 'Foghorn Club');
  });

  testWidgets('venue detail shows map, chronological events, and performers', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
    );

    expect(find.byKey(const Key('venue-detail-hero')), findsOne);
    expect(find.text('THE FOGHORN CLUB'), findsOne);
    expect(find.textContaining('2455 Harrison St'), findsNothing);
    expect(find.textContaining(DemoData.venues['v1']!.addr), findsWidgets);
    expect(find.byKey(const Key('venue-detail-distance')), findsOne);
    expect(find.byType(VenueMiniMap), findsNothing);
    expect(find.byKey(const Key('venue-map')), findsOne);
    expect(find.byKey(const Key('venue-address-line')), findsOne);
    expect(find.byKey(const Key('venue-area-line')), findsOne);
    expect(
      tester.getTopLeft(find.byKey(const Key('venue-map'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('venue-detail-hero'))).dy,
      ),
    );
    expect(find.textContaining('DOOR POLICY'), findsNothing);
    expect(find.textContaining('PAST EVENTS'), findsNothing);
    await tester.scrollUntilVisible(
      find.textContaining('UPCOMING ·'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('venue-detail-content')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('UPCOMING ·'), findsOne);
    final rows = tester
        .widgetList<FanEventCard>(find.byType(FanEventCard))
        .toList();
    final venueGigs = DemoData.gigs.where((gig) => gig.venueId == 'v1');
    expect(rows, hasLength(venueGigs.length));
    final startsAt = rows.map((card) => card.gig.startsAt).toList();
    expect(startsAt, orderedEquals([...startsAt]..sort()));

    final firstGigId = rows.first.gig.id;
    await tester.tap(find.byKey(ValueKey('fan-event-$firstGigId')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, firstGigId);
    harness.app.back();
    await tester.pump();

    await tester.drag(
      find.byKey(const Key('venue-detail-content')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('PERFORMING BANDS ·'), findsOne);
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
      repository: repository.stub,
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
      repository: StubRepository(auth: auth)
        ..returns(
          'venueDetail',
          VenueDetail(
            venue: DemoData.venues['v1']!.copyWith(photoUrls: const []),
            gigs: const [],
            bands: const {},
            truncated: false,
          ),
        ),
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
    );
    expect(find.byKey(const Key('venue-map')), findsOne);
    await tester.scrollUntilVisible(
      find.text('No performers announced yet.'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('venue-detail-content')),
        matching: find.byType(Scrollable),
      ),
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
    // The simplified card shows the date line, the location and the price
    // chip; the lineup and the venue address live on the gig page.
    expect(find.textContaining(gig.doorsLabel), findsOne);
    expect(find.textContaining('FREE'), findsOne);
    expect(find.textContaining('DOORS ${gig.doorsLabel}'), findsNothing);
    expect(find.textContaining(gig.ageRequirement.label), findsNothing);
    expect(find.byKey(const Key('lineup-see-all')), findsNothing);
    expect(find.byKey(ValueKey('share-${gig.id}')), findsNothing);
    expect(
      find.textContaining(DemoData.venues[gig.venueId]!.addr),
      findsNothing,
    );

    await tester.tap(find.byKey(ValueKey('save-${gig.id}')));
    await tester.pump();
    expect(harness.app.current.screen, Screen.auth);
    expect(harness.app.pending?.kind, PendingKind.save);
    expect(harness.app.pending?.id, gig.id);
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
    final repository = StubRepository(auth: auth)
      ..returnsStream(
        'feed',
        () => Stream.value(
          FeedSnapshot(
            gigs: [
              for (final gig in DemoData.gigs)
                if (gig.id != 'g4') gig,
            ],
            venues: DemoData.venues,
            bands: DemoData.bands,
          ),
        ),
      )
      ..returnsStream(
        'myInteractions',
        () => Stream.value(
          Interactions(
            rsvpGigIds: {'g4'},
            followBandIds: {},
            savedGigIds: {},
            gigs: [DemoData.gigs.firstWhere((gig) => gig.id == 'g4')],
            attendedCount: 0,
          ),
        ),
      );
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

/// Result rows are tall enough that later sections start below the fold.
Future<void> _scrollResultsTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(target, 200, scrollable: _resultsScrollable());

Future<void> _scrollToTop(WidgetTester tester) async {
  final scrollable = _resultsScrollable();
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(0);
  await tester.pump();
}

Finder _resultsScrollable() {
  bool isResultsList(Widget widget) {
    final key = widget.key;
    return key is ValueKey<String> &&
        (key.value.startsWith('explore-browse-') ||
            key.value.startsWith('explore-results-'));
  }

  return find
      .descendant(
        of: find.byWidgetPredicate(isResultsList),
        matching: find.byType(Scrollable),
      )
      .first;
}

// Wrap the stub to preserve the integer calls getter; StubRepository.calls is a map.
class _RetryVenueRepository {
  _RetryVenueRepository({required FakeAuthService auth})
    : stub = StubRepository(auth: auth)
        ..failOnce('venueDetail', Exception('venue failed'));

  final StubRepository stub;

  int get calls => stub.callsTo('venueDetail');
}
