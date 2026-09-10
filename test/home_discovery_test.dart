import 'dart:ui' show PointerDeviceKind;

import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

// Purging the seeded demo rows made a genuinely empty feed reachable for the
// first time, so the two reasons a feed can be empty have to read differently.
const _noGigs =
    'No upcoming gigs yet.\nWhen a band books one, it shows up here.';
const _noMatches =
    'Nothing matches those filters.\nLoosen them up and see what is out there.';

void main() {
  testWidgets('Home defaults to Map and keeps List as an intentional switch', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    expect(harness.app.mapMode, isTrue);
    expect(find.byType(GigMapView), findsOne);
    expect(findUiText('PUNK'), findsNothing);
    expect(findUiText('EARPLUG'), findsOne);

    final logo = tester.getRect(find.byKey(const Key('home-logo')));
    final wordmark = tester.getRect(find.byKey(const Key('home-wordmark')));
    final viewToggle = tester.getRect(
      find.byKey(const Key('home-view-toggle')),
    );
    final location = tester.getRect(
      find.byKey(const Key('home-location-control')),
    );
    expect(logo.right, lessThan(wordmark.left));
    expect(wordmark.right, lessThan(viewToggle.left));
    expect((logo.center.dy - wordmark.center.dy).abs(), lessThan(2));
    expect(viewToggle.bottom, lessThan(location.top));
    expect(location.left, 16);
    expect(location.right, 386);

    await tester.tap(findUiText('LIST'));
    await tester.pumpAndSettle();

    expect(harness.app.mapMode, isFalse);
    expect(find.byType(GigMapView), findsNothing);
    expect(findUiText('8 GIGS NEAR YOU · LOCAL ORDER'), findsOne);
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
  });

  testWidgets('Home identity row and location picker fit a narrow phone', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: HomeScreen()));
    tester.view.physicalSize = const Size(320, 700);
    await tester.pumpAndSettle();

    final logo = tester.getRect(find.byKey(const Key('home-logo')));
    final wordmark = tester.getRect(find.byKey(const Key('home-wordmark')));
    final viewToggle = tester.getRect(
      find.byKey(const Key('home-view-toggle')),
    );
    final location = tester.getRect(
      find.byKey(const Key('home-location-control')),
    );

    expect(logo.right, lessThan(wordmark.left));
    expect(wordmark.right, lessThan(viewToggle.left));
    expect(viewToggle.bottom, lessThan(location.top));
    expect(location.left, 16);
    expect(location.right, 304);
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

    expect(findUiText('1 GIG NEAR YOU · LOCAL ORDER'), findsOne);
    expect(findUiText('1 GIGS NEAR YOU · LOCAL ORDER'), findsNothing);
  });

  testWidgets('map markers use the same multi-genre filtered feed', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) {
        app.toggleGenre('hardcore');
        app.toggleGenre('surf');
      },
    );

    expect(harness.app.feed.map((gig) => gig.id), ['g2', 'g1', 'g4']);
    for (final id in const ['g1', 'g2', 'g4']) {
      expect(find.byKey(Key('gig-marker-$id')), findsOne);
    }
    expect(find.byKey(const Key('gig-marker-g3')), findsNothing);
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

    await tester.tap(findUiText('LIST'));
    await tester.pumpAndSettle();
    expect(findUiText('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
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
    expect(findUiText('DISCOVERY BOOST · COMPLETE LISTING'), findsNothing);

    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(harness.app.isDiscoveryBoosted(repository.gig), isTrue);
    expect(findUiText('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
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
    expect(findUiText('DISCOVERY BOOST · COMPLETE LISTING'), findsNothing);

    now = now.add(boundaryDelay);
    await tester.pump(boundaryDelay);

    expect(harness.app.isDiscoveryBoosted(repository.gig), isTrue);
    expect(findUiText('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
  });

  testWidgets('the whole map card opens one gig route', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    await _expandClusterContaining(tester, 'gig-marker-g1');
    await tester.tap(find.byKey(const Key('gig-marker-g1')));
    await tester.pumpAndSettle();
    expect(findUiText('OPEN GIG →'), findsOne);

    await tester.tap(findUiText('BASEMENT BLOWOUT'));
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
    expect(findUiText('RIPTIDE RELEASE SHOW'), findsOne);
    expect(findUiText('1 OF 2 GIGS AT THIS VENUE'), findsOne);

    await tester.tap(find.byKey(const Key('previous-map-gig')));
    await tester.pumpAndSettle();
    expect(findUiText('RIPTIDE RELEASE SHOW'), findsOne);

    await tester.tap(find.byKey(const Key('next-map-gig')));
    await tester.pumpAndSettle();
    expect(findUiText('FOG CITY FEST — DAY SHOW'), findsOne);
    expect(findUiText('2 OF 2 GIGS AT THIS VENUE'), findsOne);

    await tester.tap(find.byKey(const Key('next-map-gig')));
    await tester.pumpAndSettle();
    expect(findUiText('FOG CITY FEST — DAY SHOW'), findsOne);

    await tester.tap(findUiText('OPEN GIG →'));
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

    await tester.tap(findUiText('FILTERS'));
    await tester.pumpAndSettle();
    await toggleFormSelection(tester, 'Genres', 'punk');

    expect(harness.app.fGenres, {'punk'});
    expect(findUiText('SHOW 3 RESULTS'), findsOne);

    await tester.tap(find.byKey(const Key('show-filter-results')));
    await tester.pumpAndSettle();

    expect(find.text('ANY GENRE · I\'M OPEN'), findsNothing);
    expect(findUiText('FILTERS · 1'), findsOne);
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
    await tester.tap(findUiText('MISSION, SF'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('current-location-option')));
    await tester.pumpAndSettle();

    expect(harness.app.discoveryLocation, DiscoveryLocation.current);
    expect(find.byKey(const Key('current-location-marker')), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('zero results offer direct date and reset recovery actions', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
      beforePump: (app) {
        app.toggleDateFilter(DateFilter.tonight);
        app.toggleGenre('klezmer');
      },
    );

    expect(harness.app.feed, isEmpty);
    expect(find.text(_noMatches), findsOne);
    expect(find.text(_noGigs), findsNothing);
    expect(findUiText('SHOW THIS WEEK'), findsOne);
    expect(findUiText('CLEAR GENRES'), findsOne);
    expect(findUiText('VIEW ALL NEARBY SHOWS'), findsOne);

    await tester.tap(findUiText('SHOW THIS WEEK'));
    await tester.pumpAndSettle();
    expect(harness.app.fDate, DateFilter.week);

    await tester.tap(findUiText('VIEW ALL NEARBY SHOWS'));
    await tester.pumpAndSettle();
    expect(harness.app.filters.activeCount, 0);
    expect(harness.app.feed, isNotEmpty);
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
    expect(findUiText('0 GIGS NEAR YOU · LOCAL ORDER'), findsOne);
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

  testWidgets('compact is the default date-first card presentation', (
    tester,
  ) async {
    final gig = DemoData.gigs.firstWhere((item) => item.discoveryListingReady);
    final auth = FakeAuthService();
    final boostedBand = DemoData.bands[gig.createdByBand]!.copyWith(
      discoveryProfileReady: true,
    );
    final harness = await pumpApp(
      tester,
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
    expect(find.byType(DateBlock), findsOne);
    expect(find.byType(GigFlyer), findsNothing);
    expect(find.text('${gig.going} GOING'), findsOne);
    expect(find.byKey(ValueKey('save-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('share-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsOne);
    final boostLabel = tester.widget<Text>(
      find.byKey(ValueKey('discovery-boost-${gig.id}')),
    );
    expect(boostLabel.style!.fontSize, greaterThanOrEqualTo(11));
    final ageLabel = tester.widget<Text>(
      find.text(gig.ageRequirement.label.toUpperCase()),
    );
    expect(ageLabel.style!.fontSize, greaterThanOrEqualTo(11));
  });

  testWidgets('featured presentation uses the resolved presenter and flyer', (
    tester,
  ) async {
    final gig = DemoData.gigs.firstWhere((item) => item.createdByBand != null);
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

    final presenter = DemoData.bands[gig.createdByBand]!.name.toUpperCase();
    expect(find.byType(DateBlock), findsNothing);
    expect(find.byType(GigFlyer), findsOne);
    expect(find.text('$presenter PRESENTS'), findsOne);
    expect(find.text(gig.title.toUpperCase()), findsOne);
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsOne);
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
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsNothing);
    expect(find.byKey(ValueKey('show-qr-${gig.id}')), findsNothing);
    expect(findUiText('QR PASS'), findsNothing);
    expect(findUiText('CANCELLED'), findsWidgets);
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
