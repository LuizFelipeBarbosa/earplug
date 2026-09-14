import 'dart:ui' show PointerDeviceKind;

import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/date_names.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

// Purging the seeded demo rows made a genuinely empty feed reachable for the
// first time, so the two reasons a feed can be empty have to read differently.
const _noGigs =
    'No upcoming gigs yet.\nWhen a band books one, it shows up here.';
const _noMatches =
    'Nothing matches those filters.\nLoosen them up and see what is out there.';

Finder _hero(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void main() {
  testWidgets(
    'Home defaults to Map and keeps List as an intentional switch with location toggle geometry',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: HomeScreen()),
      );

      expect(harness.app.mapMode, isTrue);
      expect(find.byType(GigMapView), findsOne);
      expect(find.text('PUNK'), findsNothing);
      expect(find.byKey(const Key('home-logo')), findsOne);

      final logo = tester.getRect(find.byKey(const Key('home-logo')));
      final viewToggle = tester.getRect(
        find.byKey(const Key('home-view-toggle')),
      );
      final location = tester.getRect(
        find.byKey(const Key('home-location-control')),
      );
      expect(logo.right, lessThan(viewToggle.left));
      expect((logo.center.dy - viewToggle.center.dy).abs(), lessThan(6));
      expect(viewToggle.bottom, lessThan(location.top));
      expect(location.left, greaterThanOrEqualTo(EpLayout.gutter));
      expect(location.right, lessThanOrEqualTo(402 - EpLayout.gutter));

      await tester.tap(find.byKey(const Key('home-view-list')));
      await tester.pumpAndSettle();

      expect(harness.app.mapMode, isFalse);
      expect(find.byType(GigMapView), findsNothing);
      expect(_hero('9 shows near you.'), findsOne);
      final cards = tester.widgetList<FanEventCard>(find.byType(FanEventCard));
      final featured = cards.first;
      expect(featured.gig.id, harness.app.feed.first.id);
      expect(featured.presentation, FanEventCardPresentation.featured);
      expect(
        cards
            .skip(1)
            .every(
              (card) => card.presentation == FanEventCardPresentation.compact,
            ),
        isTrue,
      );
      expect(
        find.byKey(ValueKey('fan-event-${harness.app.feed.first.id}')),
        findsOne,
      );

      harness.app.resetTo(Screen.explore);
      harness.app.resetTo(Screen.home);
      expect(harness.app.mapMode, isFalse);
    },
  );

  testWidgets('Home identity row and location picker fit a narrow phone', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: HomeScreen()));
    tester.view.physicalSize = const Size(320, 700);
    await tester.pumpAndSettle();

    final logo = tester.getRect(find.byKey(const Key('home-logo')));
    final viewToggle = tester.getRect(
      find.byKey(const Key('home-view-toggle')),
    );
    final location = tester.getRect(
      find.byKey(const Key('home-location-control')),
    );

    expect(logo.right, lessThan(viewToggle.left));
    expect(viewToggle.bottom, lessThan(location.top));
    expect(location.left, greaterThanOrEqualTo(EpLayout.gutter));
    expect(location.right, lessThanOrEqualTo(320 - EpLayout.gutter));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single nearby result uses singular gig copy', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'feed',
          () => Stream.value(
            FeedSnapshot(
              gigs: [DemoData.gigs.first],
              venues: DemoData.venues,
              bands: DemoData.bands,
            ),
          ),
        ),
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) => app.setMapMode(false),
    );

    expect(_hero('1 show near you.'), findsOne);
  });

  testWidgets('map markers ignore genre filters', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) {
        app.toggleGenre('hardcore');
        app.toggleGenre('surf');
      },
    );

    expect(harness.app.feed.map((gig) => gig.id), ['g2', 'g1', 'g4']);
    expect(harness.app.homeFeed.length, harness.app.allGigs.length);
    await tester.pump(const Duration(seconds: 1));
    await _expandClusterContaining(tester, 'venue-marker-v2');
    expect(find.byKey(const Key('venue-marker-v2')), findsOne);
  });

  testWidgets('map marker hover stays on the pin inside its 48px target', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: HomeScreen()));
    await _expandClusterContaining(tester, 'venue-marker-v1');

    final button = find.byKey(const ValueKey('map-marker-button-v1'));
    expect(tester.getSize(button), const Size.square(48));

    final ink = tester.widget<InkResponse>(
      find.descendant(of: button, matching: find.byType(InkResponse)),
    );
    expect(ink.hoverColor, Colors.transparent);
    expect(ink.focusColor, Colors.transparent);
    expect(ink.highlightColor, Colors.transparent);

    final pin = find.descendant(
      of: button,
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(pin), const Size.square(26));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(button));
    await tester.pump();

    final decorations = tester
        .widgetList<Container>(
          find.descendant(of: pin, matching: find.byType(Container)),
        )
        .map((container) => container.decoration)
        .whereType<BoxDecoration>();
    final pinDecoration = decorations.firstWhere(
      (decoration) => decoration.shape == BoxShape.circle,
    );
    expect(
      pinDecoration.border,
      Border.all(color: Ep.contentPrimary, width: 2),
    );
  });

  testWidgets('active complete listings carry the transparent boost label', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final readyBand = DemoData.bands['b1']!.copyWith(
      discoveryProfileReady: true,
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'feed',
          () => Stream.value(
            FeedSnapshot(
              gigs: DemoData.gigs,
              venues: DemoData.venues,
              bands: {...DemoData.bands, 'b1': readyBand},
            ),
          ),
        )
        ..returnsStream(
          'myBands',
          () => Stream.value([BandMembership(band: readyBand, role: 'admin')]),
        ),
      home: const Scaffold(body: HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('home-view-list')));
    await tester.pumpAndSettle();
    expect(find.text('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
  });

  testWidgets('the feed refreshes when a discovery boost window opens', (
    tester,
  ) async {
    final auth = FakeAuthService();
    var now = DateTime.utc(2026, 8, 25, 19);
    final repository = _BoundaryBoostRepository(auth: auth, now: now);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) => app.setMapMode(false),
      now: () => now,
    );

    expect(harness.app.isDiscoveryBoosted(repository.gig), isFalse);
    expect(find.text('DISCOVERY BOOST · COMPLETE LISTING'), findsNothing);

    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(harness.app.isDiscoveryBoosted(repository.gig), isTrue);
    expect(find.text('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
  });

  testWidgets('a same-second boundary refreshes discovery boost membership', (
    tester,
  ) async {
    final auth = FakeAuthService();
    var now = DateTime.utc(2026, 8, 25, 19, 0, 0, 400);
    const boundaryDelay = Duration(milliseconds: 500);
    final repository = _BoundaryBoostRepository(
      auth: auth,
      now: now,
      opensAfter: boundaryDelay,
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) => app.setMapMode(false),
      now: () => now,
    );

    expect(harness.app.isDiscoveryBoosted(repository.gig), isFalse);
    expect(find.text('DISCOVERY BOOST · COMPLETE LISTING'), findsNothing);

    now = now.add(boundaryDelay);
    await tester.pump(boundaryDelay);

    expect(harness.app.isDiscoveryBoosted(repository.gig), isTrue);
    expect(find.text('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
  });

  testWidgets('the whole map card opens one gig route', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    await _expandClusterContaining(tester, 'gig-marker-g1');
    await tester.tap(find.byKey(const Key('gig-marker-g1')));
    await tester.pumpAndSettle();
    expect(find.text('OPEN GIG →'), findsOne);
    final cardFinder = find.byKey(const ValueKey('map-gig-card-g1'));
    expect(
      find.descendant(of: cardFinder, matching: find.byType(GigFlyer)),
      findsOne,
    );
    expect(
      tester.getRect(cardFinder).bottom,
      closeTo(900 - (EpLayout.tabBarHeight + 12), 1),
    );

    await tester.tap(find.text('BASEMENT BLOWOUT'));
    await tester.pumpAndSettle();

    expect(harness.app.authed, isFalse);
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, 'g1');
    harness.app.back();
    expect(harness.app.current.screen, Screen.home);
  });

  testWidgets('only tapping outside the map card dismisses it', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    await _expandClusterContaining(tester, 'gig-marker-g1');
    await tester.tap(find.byKey(const Key('gig-marker-g1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-gig-card-g1')), findsOne);

    final map = tester.getRect(find.byType(GigMapView));
    await tester.tapAt(map.topLeft + const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('map-gig-card-g1')), findsNothing);
    expect(harness.app.current.screen, Screen.home);
  });

  testWidgets('co-located gigs share a marker and remain individually usable', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label?.endsWith(' venues') ?? false),
      ),
      findsWidgets,
    );
    await _expandClusterContaining(tester, 'venue-marker-v1');
    expect(find.byKey(const Key('venue-marker-v1')), findsOne);
    expect(find.byKey(const Key('gig-marker-g2')), findsNothing);
    expect(find.byKey(const Key('gig-marker-g7')), findsNothing);

    await tester.tap(find.byKey(const Key('venue-marker-v1')));
    await tester.pumpAndSettle();
    expect(find.text('RIPTIDE RELEASE SHOW'), findsOne);
    expect(find.text('1 OF 2 GIGS AT THIS VENUE'), findsOne);

    expect(
      tester.getSize(find.byKey(const Key('previous-map-gig'))).height,
      lessThanOrEqualTo(32),
    );
    expect(
      tester.getSize(find.byKey(const Key('next-map-gig'))).height,
      lessThanOrEqualTo(32),
    );
    final card = find.byKey(const ValueKey('map-gig-card-g2'));
    final openButton = find.descendant(
      of: card,
      matching: find.widgetWithText(FilledButton, 'OPEN GIG →'),
    );
    final flyer = find.descendant(of: card, matching: find.byType(GigFlyer));
    expect(
      tester.getRect(openButton).bottom,
      closeTo(tester.getRect(flyer).bottom, 1),
    );

    await tester.tap(find.byKey(const Key('previous-map-gig')));
    await tester.pumpAndSettle();
    expect(find.text('RIPTIDE RELEASE SHOW'), findsOne);

    await tester.tap(find.byKey(const Key('next-map-gig')));
    await tester.pumpAndSettle();
    expect(find.text('FOG CITY FEST — DAY SHOW'), findsOne);
    expect(find.text('2 OF 2 GIGS AT THIS VENUE'), findsOne);

    await tester.tap(find.byKey(const Key('next-map-gig')));
    await tester.pumpAndSettle();
    expect(find.text('FOG CITY FEST — DAY SHOW'), findsOne);

    await tester.tap(find.text('OPEN GIG →'));
    await tester.pumpAndSettle();
    expect(harness.app.current.param, 'g7');
    harness.app.back();
    expect(harness.app.current.screen, Screen.home);
  });

  testWidgets('gigs without a resolved venue stay off the map', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'feed',
          () => Stream.value(
            FeedSnapshot(
              gigs: [DemoData.gigs.first, _missingVenueGig],
              venues: {'v3': DemoData.venues['v3']!},
              bands: const {},
            ),
          ),
        )
        ..returns('venues', const <Venue>[]),
      home: const Scaffold(body: HomeScreen()),
    );

    expect(find.byKey(const Key('gig-marker-g1')), findsOne);
    expect(find.byKey(const Key('gig-marker-missing-venue')), findsNothing);
  });

  testWidgets('Filters apply live and the results button closes the sheet', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('home-filters')));
    await tester.pumpAndSettle();
    expect(find.text('GENRES · CHOOSE ANY'), findsNothing);
    await tester.tap(find.text('PAID'));
    await tester.pumpAndSettle();

    expect(harness.app.fPrice, PriceFilter.paid);

    await tester.tap(find.byKey(const Key('show-filter-results')));
    await tester.pumpAndSettle();

    expect(find.text('ANY GENRE · I\'M OPEN'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('home-filters')),
        matching: find.text('1'),
      ),
      findsOne,
    );
  });

  testWidgets('quick filters fill the row and share a center line', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
      size: const Size(402, 700),
    );

    final pills = find.byType(EpPill);
    final tonight = tester.getRect(pills.at(0));
    final thisWeek = tester.getRect(pills.at(1));
    final free = tester.getRect(pills.at(2));
    final filters = tester.getRect(find.byKey(const Key('home-filters')));
    expect(
      (tonight.center.dy - thisWeek.center.dy).abs(),
      lessThanOrEqualTo(1),
    );
    expect((tonight.center.dy - free.center.dy).abs(), lessThanOrEqualTo(1));
    expect((tonight.center.dy - filters.center.dy).abs(), lessThanOrEqualTo(1));
    expect(tonight.left, EpLayout.gutter);
    expect(filters.right, 402 - EpLayout.gutter);
  });

  testWidgets('current location is user initiated and adds a map marker', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      locationService: const _SuccessfulLocationService(),
      home: const Scaffold(body: HomeScreen()),
    );

    expect(harness.app.discoveryLocation, DiscoveryLocation.sf);
    await tester.tap(find.byKey(const Key('home-location-control')));
    await tester.pumpAndSettle();

    expect(harness.app.discoveryLocation, DiscoveryLocation.current);
    expect(find.byKey(const Key('current-location-marker')), findsOne);
    expect(find.text('CURRENT LOCATION'), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('current location can be switched back to the saved scene', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      locationService: const _SuccessfulLocationService(),
      home: const Scaffold(body: HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('home-location-control')));
    await tester.pumpAndSettle();
    expect(harness.app.discoveryLocation, DiscoveryLocation.current);
    expect(find.byKey(const Key('current-location-marker')), findsOne);

    await tester.tap(find.byKey(const Key('home-location-control')));
    await tester.pumpAndSettle();
    expect(harness.app.discoveryLocation, DiscoveryLocation.sf);
    expect(find.byKey(const Key('current-location-marker')), findsNothing);
  });

  testWidgets('location failure is shown and can be dismissed', (tester) async {
    final harness = await pumpApp(
      tester,
      locationService: const _DeniedLocationService(),
      home: const Scaffold(body: HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('home-location-control')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-location-failure')), findsOne);
    expect(harness.app.discoveryLocation, DiscoveryLocation.sf);
    expect(find.text('USE MY LOCATION'), findsOne);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('home-location-failure')),
        matching: find.byTooltip('Dismiss'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-location-failure')), findsNothing);
  });

  testWidgets('zero results offer direct date and reset recovery actions', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) {
        app.useCurrentPosition(const LatLng(0, 0));
        app.setDistanceFilter(0.1);
        app.toggleDateFilter(DateFilter.tonight);
        app.toggleGenre('klezmer');
      },
    );

    expect(harness.app.homeFeed, isEmpty);
    expect(find.text(_noMatches), findsOne);
    expect(find.text(_noGigs), findsNothing);
    expect(find.text('SHOW THIS WEEK'), findsOne);
    expect(find.text('CLEAR GENRES'), findsNothing);
    expect(find.text('VIEW ALL NEARBY SHOWS'), findsOne);

    await tester.tap(find.text('SHOW THIS WEEK'));
    await tester.pumpAndSettle();
    expect(harness.app.fDate, DateFilter.week);

    await tester.tap(find.text('VIEW ALL NEARBY SHOWS'));
    await tester.pumpAndSettle();
    expect(harness.app.filters.activeCount, 0);
    expect(harness.app.homeFeed, isNotEmpty);
  });

  testWidgets('an empty backend blames nobody', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'feed',
          () =>
              Stream.value(const FeedSnapshot(gigs: [], venues: {}, bands: {})),
        ),
      home: const Scaffold(body: HomeScreen()),
    );

    expect(harness.app.allGigs, isEmpty);
    expect(find.text(_noGigs), findsOne);
    expect(find.text(_noMatches), findsNothing);
    expect(_hero('0 shows near you.'), findsOne);
  });

  testWidgets('Home list lazily builds a 60-gig feed', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final snapshot = _bigFeedSnapshot();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream('feed', () => Stream.value(snapshot)),
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) => app.setMapMode(false),
    );

    expect(tester.widgetList(find.byType(FanEventCard)).length, lessThan(60));
  });

  testWidgets('compact is the default thumbnail card presentation', (
    tester,
  ) async {
    final gig = DemoData.gigs.firstWhere((item) => item.discoveryListingReady);
    final auth = FakeAuthService();
    final boostedBand = DemoData.bands[gig.createdByBand]!.copyWith(
      discoveryProfileReady: true,
    );
    final harness = await pumpApp(
      tester,
      size: const Size(390, 900),
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returnsStream(
          'feed',
          () => Stream.value(
            FeedSnapshot(
              gigs: DemoData.gigs,
              venues: DemoData.venues,
              bands: {...DemoData.bands, gig.createdByBand!: boostedBand},
            ),
          ),
        )
        ..returnsStream(
          'myBands',
          () =>
              Stream.value([BandMembership(band: boostedBand, role: 'admin')]),
        ),
      now: () => gig.startsAt.subtract(const Duration(days: 1)),
      home: Builder(
        builder: (context) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(gig: gig, app: context.watch<AppState>()),
          ),
        ),
      ),
    );

    expect(harness.app.isDiscoveryBoosted(gig), isTrue);
    final card = tester.widget<FanEventCard>(find.byType(FanEventCard));
    expect(card.presentation, FanEventCardPresentation.compact);
    expect(
      find.descendant(
        of: find.byType(FanEventCard),
        matching: find.byType(ExploreEventRow),
      ),
      findsOne,
    );
    final thumbnail = find.descendant(
      of: find.byType(FanEventCard),
      matching: find.byType(EpNetworkImage),
    );
    final thumbnailSize = tester.getSize(thumbnail);
    final rowHeight = tester.getSize(find.byType(ExploreEventRow)).height;
    expect(thumbnailSize.width, 96);
    expect(thumbnailSize.height, closeTo(rowHeight - 25, 0.1));
    expect(find.byType(GigFlyer), findsOneWidget);
    expect(
      find.textContaining(
        '${gig.startsAt.day} ${monthNamesUpper[gig.startsAt.month - 1]}',
      ),
      findsOne,
    );
    expect(find.textContaining(gig.doorsLabel), findsOne);
    expect(find.textContaining(gig.priceLabel), findsOne);
    expect(
      find.descendant(
        of: find.byType(FanEventCard),
        matching: find.byType(EpAvatarTile),
      ),
      findsWidgets,
    );
    expect(
      find.textContaining(gig.ageRequirement.label.toUpperCase()),
      findsNothing,
    );
    expect(find.textContaining('${gig.going} GOING'), findsNothing);
    expect(find.byKey(ValueKey('save-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('share-${gig.id}')), findsOne);
    expect(harness.app.rsvps, isNot(contains(gig.id)));
    expect(find.byKey(ValueKey('discovery-boost-${gig.id}')), findsOne);
    expect(find.text('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
  });

  testWidgets('featured presentation renders the explore featured card', (
    tester,
  ) async {
    final gig = DemoData.gigs.firstWhere((item) => item.flyerUrl == null);
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(
              gig: gig,
              app: context.read<AppState>(),
              presentation: FanEventCardPresentation.featured,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ExploreFeaturedCard), findsOne);
    expect(find.byType(EpDateBlock), findsNothing);
    expect(find.byType(DateBlock), findsNothing);
    expect(find.byType(GigFlyer), findsOne);
    expect(find.text(gig.title.toUpperCase()), findsOne);
  });

  testWidgets('cancelled future RSVP still surfaces in the upcoming profile', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final cancelledGig = DemoData.gigs
        .firstWhere(
          (gig) =>
              gig.tix == Ticketing.rsvp && gig.startsAt.isAfter(DateTime.now()),
        )
        .copyWith(lifecycle: GigLifecycle.cancelled);
    final repository = StubRepository(auth: auth)
      ..returnsStream(
        'feed',
        () => Stream.value(
          FeedSnapshot(
            gigs: [
              for (final gig in DemoData.gigs)
                if (gig.id == cancelledGig.id) cancelledGig else gig,
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
            rsvpGigIds: {cancelledGig.id},
            followBandIds: const {},
            savedGigIds: const {},
            gigs: [cancelledGig],
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

    final gig = cancelledGig;
    await tester.pumpAndSettle();
    expect(harness.app.rsvps, contains(gig.id));
    expect(harness.app.upcomingRsvpGigs.map((g) => g.id), [gig.id]);
    expect(find.byKey(ValueKey('next-show-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('fan-event-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('show-qr-${gig.id}')), findsNothing);
    expect(find.text('QR PASS'), findsNothing);
    expect(find.text('CANCELLED'), findsWidgets);
  });
}

Future<void> _expandClusterContaining(
  WidgetTester tester,
  String memberKey,
) async {
  final marker = find.byKey(Key(memberKey));
  for (var attempt = 0; attempt < 4 && marker.evaluate().isEmpty; attempt++) {
    final cluster = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('venue-cluster-') &&
          key.value.contains(memberKey);
    });
    expect(cluster, findsWidgets);
    await tester.tap(cluster.first);
    await tester.pumpAndSettle();
  }
  expect(marker, findsOne);
}

FeedSnapshot _bigFeedSnapshot() {
  return FeedSnapshot(
    gigs: List.generate(60, (index) {
      final source = DemoData.gigs.first;
      return Gig(
        id: 'big-$index',
        slug: 'big-$index',
        title: source.title,
        venueId: source.venueId,
        price: source.price,
        startsAt: source.startsAt,
        doorsAt: source.doorsAt,
        dateShort: source.dateShort,
        dateLine: source.dateLine,
        time: source.time,
        when: source.when,
        flyKey: source.flyKey,
        lineup: source.lineup,
        performers: source.performers,
        going: source.going,
        genres: source.genres,
        desc: source.desc,
        tix: source.tix,
        externalUrl: source.externalUrl,
        flyerUrl: source.flyerUrl,
        cap: source.cap,
        ageRequirement: source.ageRequirement,
        lifecycle: source.lifecycle,
        createdByBand: source.createdByBand,
        discoveryListingReady: source.discoveryListingReady,
      );
    }),
    venues: DemoData.venues,
    bands: DemoData.bands,
  );
}

class _SuccessfulLocationService implements LocationService {
  const _SuccessfulLocationService();

  @override
  Future<LocationResult> requestCurrentLocation() async =>
      const LocationSuccess(
        UserLocation(
          latitude: 37.7524,
          longitude: -122.4180,
          accuracyMeters: 5,
        ),
      );

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _DeniedLocationService implements LocationService {
  const _DeniedLocationService();

  @override
  Future<LocationResult> requestCurrentLocation() async =>
      const LocationFailure(LocationFailureReason.permissionDenied);

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _BoundaryBoostRepository extends StubRepository {
  _BoundaryBoostRepository({
    required super.auth,
    required DateTime now,
    Duration opensAfter = const Duration(seconds: 2),
  }) : opensAt = now.add(opensAfter) {
    final readyBand = DemoData.bands['b1']!.copyWith(
      discoveryProfileReady: true,
    );
    returnsStream(
      'feed',
      () => Stream.value(
        FeedSnapshot(
          gigs: [gig],
          venues: {'v1': DemoData.venues['v1']!},
          bands: {'b1': readyBand},
        ),
      ),
    );
    returnsStream(
      'myBands',
      () => Stream.value([BandMembership(band: readyBand, role: 'admin')]),
    );
  }

  final DateTime opensAt;

  late final Gig gig = DemoData.gigs[1].copyWith(
    startsAt: opensAt.add(discoveryBoostLead),
  );
}

final _missingVenueGig = Gig(
  id: 'missing-venue',
  title: 'Nowhere Show',
  venueId: 'deleted-venue',
  price: 0,
  startsAt: DemoData.gigs.first.startsAt.add(const Duration(hours: 1)),
  dateShort: DemoData.gigs.first.dateShort,
  dateLine: DemoData.gigs.first.dateLine,
  time: DemoData.gigs.first.time,
  when: DemoData.gigs.first.when,
  flyKey: DemoData.gigs.first.flyKey,
  lineup: DemoData.gigs.first.lineup,
  going: 0,
  genres: DemoData.gigs.first.genres,
  desc: 'The venue row was deleted.',
  tix: Ticketing.rsvp,
);
