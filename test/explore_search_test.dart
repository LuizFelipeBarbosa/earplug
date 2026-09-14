import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

const _directoryOnlyVenue = Venue(
  id: 'v-derby',
  name: 'Derby Street House',
  area: 'South Berkeley',
  addr: '2863 Derby St, Berkeley',
  point: LatLng(37.8614, -122.2508),
);

void main() {
  testWidgets('typing keeps a local draft until the search button is tapped', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
      beforePump: (app) => app.loadMoreExploreBands(),
    );

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      '  Mission Creep  ',
    );
    await tester.pump();
    expect(harness.app.query, isEmpty);
    expect(find.text('GENRES'), findsNothing);
    expect(find.text('PUNK'), findsNothing);

    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();
    expect(harness.app.query, 'Mission Creep');
    await tester.scrollUntilVisible(
      find.text('MISSION CREEP'),
      200,
      scrollable: _allResultsScrollable(),
    );
    expect(find.text('MISSION CREEP'), findsOne);
    expect(find.text('GENRES'), findsNothing);
  });

  testWidgets('keyboard search submits and clear restores browsing', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
      beforePump: (app) => app.loadMoreExploreBands(),
    );
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'Foghorn',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(harness.app.query, 'Foghorn');
    await tester.scrollUntilVisible(
      find.text('FOGHORN DIET'),
      200,
      scrollable: _allResultsScrollable(),
    );
    expect(find.text('FOGHORN DIET'), findsOne);
    await _scrollToTop(tester);
    await tester.tap(find.byKey(const Key('explore-search-clear')));
    await tester.pumpAndSettle();
    expect(harness.app.query, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('explore-search-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('GENRES'), findsNothing);
  });

  testWidgets('band rows use singular fan copy for a single follower', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns(
          'listBands',
          BandPage(
            items: [
              bandFixture(
                id: 'one-fan-band',
                slug: 'one-fan-band',
                name: 'One Fan Band',
                area: 'Berkeley',
                color: const Color(0xFF2233EE),
                initials: 'OF',
              ),
            ],
            continueCursor: null,
            isDone: true,
          ),
        ),
      home: const Scaffold(body: ExploreScreen()),
      beforePump: (app) => app.loadMoreExploreBands(),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'One Fan Band',
    );
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 fan'), findsOne);
    expect(find.textContaining('1 fans'), findsNothing);
  });

  testWidgets('genre rail scopes Explore events and clears back to browse', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    await tester.ensureVisible(find.byKey(const Key('explore-genre-noise')));
    await tester.tap(find.byKey(const Key('explore-genre-noise')));
    await tester.pumpAndSettle();
    expect(harness.app.exploreGenre, 'noise');
    expect(find.byKey(const Key('explore-genre-page')), findsOne);
    expect(
      find.byKey(const ValueKey('fan-event-g1'), skipOffstage: false),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('fan-event-g5'), skipOffstage: false),
      findsNothing,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('explore-genre-all')),
      -200,
      scrollable: find.descendant(
        of: find.byKey(const Key('explore-genre-rail-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.drag(
      find.byKey(const Key('explore-genre-rail-list')),
      const Offset(200, 0),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('explore-genre-all')));
    await tester.pumpAndSettle();
    expect(harness.app.exploreGenre, isNull);
  });

  testWidgets('later published gigs appear and stay live in Explore', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _LiveExploreRepository(auth: auth);
    addTearDown(repository.close);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: ExploreScreen()),
    );
    expect(find.text('TESS'), findsNothing);
    repository.publishTess();
    await tester.pumpAndSettle();
    expect(
      harness.app.feed.map((gig) => gig.id),
      contains('tess-september-23'),
    );
    final tess = find.byKey(const Key('explore-for-you-tess-september-23'));
    await tester.scrollUntilVisible(tess, 300, scrollable: _browseScrollable());
    expect(tess, findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('explore-genre-noise')));
    await tester.tap(find.byKey(const Key('explore-genre-noise')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore-genre-page')), findsOne);
    expect(find.text('TESS'), findsNothing);
    await tester.tap(find.byKey(const Key('explore-genre-all')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('explore-for-you-tess-september-23')),
      findsOne,
    );
  });

  testWidgets('search results construct off-screen rows lazily', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: ExploreScreen()));
    await tester.enterText(find.byKey(const Key('explore-search-field')), 'a');
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();
    final results = find.byKey(const Key('explore-results-search'));
    final scroll = tester.widget<CustomScrollView>(results);
    final lists = scroll.slivers.whereType<SliverList>();
    expect(lists.single.delegate, isA<SliverChildBuilderDelegate>());
    expect(find.text('SUNSET BUNKER'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('SUNSET BUNKER'),
      400,
      scrollable: _allResultsScrollable(),
    );
    expect(find.text('SUNSET BUNKER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the bands and venues rows opens their collections', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    final bandsToggle = find.byKey(const Key('explore-toggle-bands'));
    await tester.scrollUntilVisible(
      bandsToggle,
      250,
      scrollable: _browseScrollable(),
    );
    await tester.tap(bandsToggle);
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.exploreCollection);
    expect(harness.app.current.param, 'bands');
    final venuesHarness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    final venuesToggle = find.byKey(const Key('explore-toggle-venues'));
    await tester.scrollUntilVisible(
      venuesToggle,
      250,
      scrollable: _browseScrollable(),
    );
    await tester.tap(venuesToggle);
    await tester.pumpAndSettle();
    expect(venuesHarness.app.current.screen, Screen.exploreCollection);
    expect(venuesHarness.app.current.param, 'venues');
  });

  testWidgets('search finds a venue that has no gigs', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _directoryRepository(auth),
      home: const Scaffold(body: ExploreScreen()),
    );
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      _directoryOnlyVenue.name,
    );
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();
    expect(find.text('VENUES · 1'), findsOne);
    expect(find.text(_directoryOnlyVenue.name.toUpperCase()), findsOne);
    expect(find.textContaining('EVENTS ·'), findsNothing);
  });

  testWidgets('a failed directory never blanks feed venues', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'feed',
          () => Stream.value(
            FeedSnapshot(
              gigs: [DemoData.gigs.firstWhere((gig) => gig.venueId == 'v1')],
              venues: {'v1': DemoData.venues['v1']!},
              bands: const {},
            ),
          ),
        )
        ..fail('venues', Exception('venue directory failed')),
      home: const Scaffold(body: ExploreScreen()),
    );
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      DemoData.venues['v1']!.name,
    );
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();
    expect(find.text(DemoData.venues['v1']!.name.toUpperCase()), findsOne);
    expect(harness.app.query, DemoData.venues['v1']!.name);
  });

  testWidgets('featured carousel shows cards and opens a gig', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    final carousel = find.byKey(const Key('explore-featured'));
    expect(carousel, findsOne);
    expect(find.byKey(const Key('explore-featured-g1')), findsOne);
    expect(find.byKey(const Key('explore-featured-g2')), findsOne);
    expect(find.byKey(const Key('explore-featured-g3')), findsNothing);
    await tester.tap(find.byKey(const Key('explore-featured-g1')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.gig);
  });

  testWidgets('location search sets city and clears query', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'Oakland',
    );
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();
    final oak = find.byKey(const Key('explore-location-oak'));
    expect(oak, findsOne);
    await tester.tap(oak);
    await tester.pumpAndSettle();
    expect(harness.app.query, isEmpty);
    expect(harness.app.discoveryLocation, DiscoveryLocation.oak);
  });
}

Finder _allResultsScrollable() => find
    .descendant(
      of: find.byKey(const Key('explore-results-search')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollToTop(WidgetTester tester) async {
  final scrollable = _allResultsScrollable();
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(0);
  await tester.pump();
}

Finder _browseScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('explore-browse-all')),
      matching: find.byType(Scrollable),
    )
    .first;

class _LiveExploreRepository extends DemoRepository {
  _LiveExploreRepository({required super.auth});

  final StreamController<FeedSnapshot> _controller =
      StreamController<FeedSnapshot>.broadcast();
  List<Gig> _gigs = List<Gig>.of(DemoData.gigs);

  FeedSnapshot get _snapshot => FeedSnapshot(
    gigs: List.unmodifiable(_gigs),
    venues: DemoData.venues,
    bands: DemoData.bands,
  );

  @override
  Stream<FeedSnapshot> feed() async* {
    yield _snapshot;
    yield* _controller.stream;
  }

  void publishTess() {
    final startsAt = DateTime.now().add(const Duration(days: 22));
    _gigs = [
      ..._gigs,
      gigFixture(
        id: 'tess-september-23',
        title: 'Tess',
        price: 12,
        startsAt: startsAt,
        when: GigWhen.later,
        lineup: const ['b1'],
        genres: const ['punk'],
        desc: 'A later published show.',
        createdByBand: 'b1',
        discoveryListingReady: true,
      ),
    ];
    _controller.add(_snapshot);
  }

  Future<void> close() => _controller.close();
}

EarplugRepository _directoryRepository(FakeAuthService auth) =>
    StubRepository(auth: auth)
      ..returns('venues', [...DemoData.venues.values, _directoryOnlyVenue]);
