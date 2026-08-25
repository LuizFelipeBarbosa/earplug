import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

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
    expect(find.text('PUNK'), findsNothing);

    await tester.tap(find.text('LIST'));
    await tester.pumpAndSettle();

    expect(harness.app.mapMode, isFalse);
    expect(find.byType(GigMapView), findsNothing);
    expect(find.text('7 GIGS NEAR YOU · LOCAL ORDER'), findsOne);

    harness.app.resetTo(Screen.explore);
    harness.app.resetTo(Screen.home);
    expect(harness.app.mapMode, isFalse);
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

  testWidgets('active complete listings carry the transparent boost label', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _BoostRepository(auth: auth),
      home: const Scaffold(body: HomeScreen()),
    );

    await tester.tap(find.text('LIST'));
    await tester.pumpAndSettle();
    expect(find.text('DISCOVERY BOOST · COMPLETE LISTING'), findsOne);
  });

  testWidgets('a guest can open an event from its map card', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    await tester.tap(find.byKey(const Key('gig-marker-g1')));
    await tester.pumpAndSettle();
    expect(find.text('OPEN GIG →'), findsOne);

    await tester.tap(find.text('OPEN GIG →'));
    await tester.pumpAndSettle();

    expect(harness.app.authed, isFalse);
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, 'g1');
  });

  testWidgets('co-located gigs share a marker and remain individually usable', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );

    expect(find.byKey(const Key('venue-marker-v1')), findsOne);
    expect(find.byKey(const Key('gig-marker-g2')), findsNothing);
    expect(find.byKey(const Key('gig-marker-g7')), findsNothing);

    await tester.tap(find.byKey(const Key('venue-marker-v1')));
    await tester.pumpAndSettle();
    expect(find.text('RIPTIDE RELEASE SHOW'), findsOne);
    expect(find.text('1 OF 2 GIGS AT THIS VENUE'), findsOne);

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
  });

  testWidgets('gigs without a resolved venue stay off the map', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _MissingVenueRepository(auth: auth),
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

    await tester.tap(find.text('FILTERS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PUNK'));
    await tester.pumpAndSettle();

    expect(harness.app.fGenres, {'punk'});
    expect(find.text('SHOW 3 RESULTS'), findsOne);

    await tester.tap(find.byKey(const Key('show-filter-results')));
    await tester.pumpAndSettle();

    expect(find.text('ANY GENRE · I\'M OPEN'), findsNothing);
    expect(find.text('FILTERS · 1'), findsOne);
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
    await tester.tap(find.text('MISSION, SF ▾'));
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

    expect(find.text('SHOW THIS WEEK'), findsOne);
    expect(find.text('CLEAR GENRES'), findsOne);
    expect(find.text('VIEW ALL NEARBY SHOWS'), findsOne);

    await tester.tap(find.text('SHOW THIS WEEK'));
    await tester.pumpAndSettle();
    expect(harness.app.fDate, DateFilter.week);

    await tester.tap(find.text('VIEW ALL NEARBY SHOWS'));
    await tester.pumpAndSettle();
    expect(harness.app.filters.activeCount, 0);
    expect(harness.app.feed, isNotEmpty);
  });
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

class _MissingVenueRepository extends DemoRepository {
  _MissingVenueRepository({required super.auth});

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: [DemoData.gigs.first, _missingVenueGig],
      venues: {'v3': DemoData.venues['v3']!},
      bands: const {},
    ),
  );

  @override
  Future<List<Venue>> venues() async => const [];
}

class _BoostRepository extends DemoRepository {
  _BoostRepository({required super.auth});

  Band get _readyBand =>
      DemoData.bands['b1']!.copyWith(discoveryProfileReady: true);

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: DemoData.gigs,
      venues: DemoData.venues,
      bands: {...DemoData.bands, 'b1': _readyBand},
    ),
  );

  @override
  Stream<List<BandMembership>> myBands() =>
      Stream.value([BandMembership(band: _readyBand, role: 'admin')]);
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
