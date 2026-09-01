import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('typing keeps a local draft until the search button is tapped', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    expect(harness.app.exploreResultType.name, 'all');
    for (final scope in const ['all', 'events', 'bands', 'venues']) {
      expect(find.byKey(ValueKey('explore-tab-$scope')), findsOne);
    }
    expect(find.byKey(const Key('explore-filter-button')), findsOne);

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
    );

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'Foghorn',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(harness.app.query, 'Foghorn');
    expect(find.text('FOGHORN DIET'), findsOne);

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
    expect(find.byKey(const Key('explore-filter-button')), findsOne);
    expect(find.text('GENRES'), findsNothing);
  });

  testWidgets('scope changes keep results visible and announce progress', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: ExploreScreen()));

    await tester.enterText(find.byKey(const Key('explore-search-field')), 'a');
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('explore-tab-events')));
    await tester.pump();

    expect(find.byKey(const Key('explore-results-events')), findsOne);
    expect(find.byKey(const Key('explore-scope-progress')), findsOne);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('explore-scope-progress')), findsNothing);
  });

  testWidgets('band rows use singular fan copy for a single follower', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _SingleFollowerRepository(auth: auth),
      home: const Scaffold(body: ExploreScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1 fan'), findsOne);
    expect(find.textContaining('1 fans'), findsNothing);
  });

  testWidgets('one accessible filter control applies and resets filters', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );
    final button = find.byKey(const Key('explore-filter-button'));

    expect(tester.getSize(button), const Size(48, 48));
    var data = tester.getSemantics(button).getSemanticsData();
    expect(data.label, 'Filters, none applied');
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isSelected, Tristate.isFalse);

    tester
        .getSemantics(button)
        .owner!
        .performAction(tester.getSemantics(button).id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    for (final label in const [
      'DATE',
      'GENRES · CHOOSE ANY',
      'DISTANCE',
      'PRICE',
      'PUNK',
      'GARAGE',
      'NOISE',
    ]) {
      expect(find.text(label), findsOne);
    }
    expect(find.textContaining('APPLY FILTERS ·'), findsOne);

    await tester.tap(find.text('PUNK'));
    await tester.pump();
    expect(harness.app.fGenres, {'punk'});
    expect(harness.app.query, isEmpty);
    await tester.scrollUntilVisible(
      find.text('VENUE'),
      280,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('VENUE'), findsOne);
    await tester.scrollUntilVisible(
      find.text('CLEAR ALL'),
      280,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('CLEAR ALL'), findsOne);
    await tester.tap(find.byKey(const Key('show-filter-results')));
    await tester.pumpAndSettle();

    data = tester.getSemantics(button).getSemanticsData();
    expect(data.label, 'Filters, 1 active');
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
    expect(find.text('PUNK'), findsNothing);

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('CLEAR ALL'),
      280,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('CLEAR ALL'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('show-filter-results')));
    await tester.pumpAndSettle();

    expect(harness.app.activeFilterCount, 0);
    data = tester.getSemantics(button).getSemanticsData();
    expect(data.label, 'Filters, none applied');
    expect(data.flagsCollection.isSelected, Tristate.isFalse);
    semantics.dispose();
  });

  testWidgets('genre filters keep Explore events on existing feed logic', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    expect(find.byKey(const ValueKey('explore-event-g1')), findsOne);
    expect(find.byKey(const ValueKey('explore-event-g5')), findsOne);

    harness.app.toggleGenre('noise');
    await tester.pump();

    expect(harness.app.feed.map((gig) => gig.id), containsAll(['g1', 'g3']));
    expect(find.byKey(const ValueKey('explore-event-g1')), findsOne);
    expect(find.byKey(const ValueKey('explore-event-g5')), findsNothing);
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
    await tester.tap(find.byKey(const ValueKey('explore-tab-events')));
    await tester.pump();
    final events = find.byKey(const ValueKey('explore-browse-events'));
    for (
      var attempt = 0;
      attempt < 6 && find.textContaining('UPCOMING').evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(events, const Offset(0, -300));
      await tester.pump();
    }
    expect(find.textContaining('UPCOMING'), findsOne);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('explore-event-tess-september-23')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('TESS'), findsOne);

    harness.app.toggleGenre('noise');
    await tester.pump();
    expect(find.text('TESS'), findsNothing);
    harness.app.toggleGenre('noise');
    await tester.pump();
    expect(
      harness.app.feed.map((gig) => gig.id),
      contains('tess-september-23'),
    );
  });

  testWidgets('browse scopes share one bounded directory and keep filters', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    expect(find.byKey(const Key('explore-event-g1')), findsOne);
    expect(find.byKey(const Key('explore-toggle-bands')), findsOne);
    expect(find.byKey(const Key('explore-toggle-venues')), findsOne);

    await tester.tap(find.byKey(const Key('explore-tab-bands')));
    await tester.pump();
    expect(harness.app.exploreResultType.name, 'bands');
    expect(find.byKey(const Key('explore-event-g1')), findsNothing);
    expect(find.byKey(const Key('explore-toggle-bands')), findsOne);
    expect(find.byKey(const Key('explore-toggle-venues')), findsNothing);

    await tester.tap(find.byKey(const Key('explore-tab-all')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('explore-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('FILTERS'), findsOne);
  });

  testWidgets('search results construct off-screen rows lazily', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: ExploreScreen()));

    await tester.enterText(find.byKey(const Key('explore-search-field')), 'a');
    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();

    final results = find.byKey(const Key('explore-results-all'));
    final list = tester.widget<ListView>(results);
    expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
    expect(find.text('SUNSET BUNKER'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('SUNSET BUNKER'),
      400,
      scrollable: _allResultsScrollable(),
    );

    expect(find.text('SUNSET BUNKER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('band and venue previews expand and collapse in place', (
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
      scrollable: find.byType(Scrollable).first,
    );
    final sectionRight =
        tester.view.physicalSize.width / tester.view.devicePixelRatio - 16;
    expect(tester.getTopRight(bandsToggle).dx, closeTo(sectionRight, .01));
    expect(find.text(DemoData.bands['b6']!.name.toUpperCase()), findsNothing);

    final previewBandIds = harness.app.exploreBandIds.take(2).toList();
    final firstBand = find.byKey(
      ValueKey('explore-band-card-${previewBandIds.first}'),
    );
    final secondBand = find.byKey(
      ValueKey('explore-band-card-${previewBandIds.last}'),
    );
    expect(
      tester.getTopLeft(secondBand).dy - tester.getBottomLeft(firstBand).dy,
      7,
    );
    expect(
      find.byKey(ValueKey('explore-follow-${previewBandIds.first}')),
      findsOne,
    );

    await tester.tap(bandsToggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-all-bands')), findsOne);
    expect(find.text(DemoData.bands['b6']!.name.toUpperCase()), findsOne);
    expect(find.text('SEE LESS BANDS'), findsOne);

    await tester.tap(bandsToggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-band-preview')), findsOne);
    expect(find.text('SEE ALL BANDS'), findsOne);

    final venuesToggle = find.byKey(const Key('explore-toggle-venues'));
    await tester.scrollUntilVisible(
      venuesToggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.getTopRight(venuesToggle).dx, closeTo(sectionRight, .01));
    expect(find.text(DemoData.venues['v6']!.name.toUpperCase()), findsNothing);

    await tester.tap(venuesToggle);
    await tester.pumpAndSettle();

    expect(find.text(DemoData.venues['v6']!.name.toUpperCase()), findsOne);
    expect(find.text('SEE LESS VENUES'), findsOne);
  });
}

Finder _allResultsScrollable() => find.descendant(
  of: find.byKey(const Key('explore-results-all')),
  matching: find.byType(Scrollable),
);

class _SingleFollowerRepository extends DemoRepository {
  _SingleFollowerRepository({required super.auth});

  @override
  Future<BandPage> listBands({String? cursor, int numItems = 50}) async =>
      const BandPage(
        items: [
          Band(
            id: 'one-fan-band',
            slug: 'one-fan-band',
            name: 'One Fan Band',
            genres: ['punk'],
            area: 'Berkeley',
            color: Color(0xFF2233EE),
            initials: 'OF',
            followers: 1,
            bio: '',
          ),
        ],
        continueCursor: null,
        isDone: true,
      );
}

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
      Gig(
        id: 'tess-september-23',
        title: 'Tess',
        venueId: 'v1',
        price: 12,
        startsAt: startsAt,
        dateShort: Gig.dateShortFor(startsAt.millisecondsSinceEpoch),
        dateLine: Gig.dateLineFor(startsAt.millisecondsSinceEpoch, '8PM / 9PM'),
        time: '8PM / 9PM',
        when: GigWhen.later,
        flyKey: 'paper',
        lineup: const ['b1'],
        going: 0,
        genres: const ['punk'],
        desc: 'A later published show.',
        tix: Ticketing.rsvp,
        lifecycle: GigLifecycle.published,
        createdByBand: 'b1',
        discoveryListingReady: true,
      ),
    ];
    _controller.add(_snapshot);
  }

  Future<void> close() => _controller.close();
}
