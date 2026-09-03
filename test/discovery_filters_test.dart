import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('discovery filters', () {
    test(
      'starts on Map and combines multi-genre filters with OR semantics',
      () async {
        final app = await _app();

        expect(app.mapMode, isTrue);
        app.toggleGenre('hardcore');
        app.toggleGenre('surf');

        expect(app.feed.map((gig) => gig.id), ['g2', 'g1', 'g4']);
        app.toggleFree();
        expect(app.feed.map((gig) => gig.id), ['g1']);
      },
    );

    test('custom date ranges include the whole selected end date', () async {
      final app = await _app();
      final selected = DemoData.gigs[1].startsAt;

      app.setDateRange(DateTimeRange(start: selected, end: selected));

      expect(app.fDate, DateFilter.custom);
      expect(app.feed.map((gig) => gig.id), ['g2']);
    });

    test('manual city selection prioritizes the nearest scene', () async {
      final app = await _app();

      expect(app.feed.first.venueId, 'v1');
      _expectLabelsFollowDistanceOrder(app);
      app.setCity('oak');

      expect(app.feed.first.venueId, 'v2');
      _expectLabelsFollowDistanceOrder(app);
    });

    test('custom dates stop before a partially loaded calendar day', () async {
      final latest = DemoData.gigs
          .map((gig) => gig.startsAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final app = await _app(
        nextFeedStartsAt: latest.add(const Duration(hours: 1)),
      );
      final expectedLast = DateTime(latest.year, latest.month, latest.day - 1);

      expect(app.lastSelectableDiscoveryDate, expectedLast);

      app.setDateRange(DateTimeRange(start: latest, end: latest));
      expect(
        app.fDateRange,
        DateTimeRange(start: expectedLast, end: expectedLast),
      );
    });

    test('custom dates include a fully loaded final calendar day', () async {
      final latest = DemoData.gigs
          .map((gig) => gig.startsAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final app = await _app(
        nextFeedStartsAt: DateTime(latest.year, latest.month, latest.day + 1),
      );

      expect(
        app.lastSelectableDiscoveryDate,
        DateTime(latest.year, latest.month, latest.day),
      );
    });

    test('custom dates allow today for an exhaustive empty feed', () async {
      final app = await _app(feedGigs: const []);

      expect(app.canSelectCustomDate, isTrue);
      expect(app.lastSelectableDiscoveryDate, app.firstSelectableDiscoveryDate);
    });

    test('custom dates disable when today is only partially loaded', () async {
      final todayGig = DemoData.gigs.first;
      final app = await _app(
        feedGigs: [todayGig],
        nextFeedStartsAt: todayGig.startsAt.add(const Duration(hours: 1)),
      );

      expect(app.canSelectCustomDate, isFalse);
      app.setDateRange(
        DateTimeRange(start: todayGig.startsAt, end: todayGig.startsAt),
      );
      expect(app.fDate, DateFilter.all);
      expect(app.fDateRange, isNull);
    });

    test(
      'GPS distance uses venue coordinates and manual city clears it',
      () async {
        final venue = DemoData.venues['v1']!;
        final location = _FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: venue.point.latitude,
              longitude: venue.point.longitude,
              accuracyMeters: 5,
            ),
          ),
        );
        final app = await _app(locationService: location);

        expect(await app.selectCurrentLocation(), isTrue);
        app.setDistanceFilter(1);

        expect(app.discoveryLocation, DiscoveryLocation.current);
        expect(app.fMaxDistanceMiles, 1);
        expect(
          app.feed.every(
            (gig) => app.distanceMilesFromCurrent(app.venue(gig.venueId))! <= 1,
          ),
          isTrue,
        );

        app.setCity('oak');
        expect(app.discoveryLocation, DiscoveryLocation.oak);
        expect(app.fMaxDistanceMiles, isNull);
      },
    );

    test('home distance filters use the saved fan city', () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final app = AppState.demo(
        repository: DemoRepository(auth: auth),
        auth: auth,
      );
      addTearDown(app.dispose);
      await pumpEventQueue();

      final saved = await app.saveFanProfile(
        name: 'Fan',
        bio: null,
        homeLocation: FanCity.berkeley,
        genres: const [],
        locationPersonalizationEnabled: true,
        followedBandUpdatesEnabled: true,
      );

      expect(saved, isTrue);
      expect(app.discoveryLocation, DiscoveryLocation.home);
      expect(app.discoveryCenter, FanCity.berkeley.center);
      expect(app.distanceOf(DemoData.venues['v2']!), '3.7 mi');
      // v1 is a private-location venue; its public point is the neighborhood centroid.
      expect(app.distanceOf(DemoData.venues['v1']!), '10.9 mi');

      app.setDistanceFilter(5);

      expect(app.feed.map((gig) => gig.id), contains('g3'));
      expect(app.feed.map((gig) => gig.id), isNot(contains('g2')));

      app.setDistanceFilter(12);

      expect(app.feed.map((gig) => gig.id), contains('g2'));
    });

    test('saved home city remains available after switching away', () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final app = AppState.demo(
        repository: DemoRepository(auth: auth),
        auth: auth,
      );
      addTearDown(app.dispose);
      await pumpEventQueue();

      final saved = await app.saveFanProfile(
        name: 'Fan',
        bio: null,
        homeLocation: FanCity.berkeley,
        genres: const [],
        locationPersonalizationEnabled: true,
        followedBandUpdatesEnabled: true,
      );

      expect(saved, isTrue);
      app.setCity('sf');

      expect(app.profile?.homeLocation, FanCity.berkeley);
      expect(app.discoveryLocation, DiscoveryLocation.sf);

      app.selectFanCity(FanCity.berkeley);

      expect(app.discoveryLocation, DiscoveryLocation.home);
      expect(app.discoveryCenter, FanCity.berkeley.center);
    });

    test('saved home city with a dedicated tile uses that location', () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final app = AppState.demo(
        repository: DemoRepository(auth: auth),
        auth: auth,
      );
      addTearDown(app.dispose);
      await pumpEventQueue();

      final saved = await app.saveFanProfile(
        name: 'Fan',
        bio: null,
        homeLocation: FanCity.sf,
        genres: const [],
        locationPersonalizationEnabled: true,
        followedBandUpdatesEnabled: true,
      );

      expect(saved, isTrue);
      expect(discoveryLocationForFanCity(FanCity.sf), DiscoveryLocation.sf);

      app.selectFanCity(FanCity.sf);

      expect(app.discoveryLocation, DiscoveryLocation.sf);
    });

    test('saved home city without a dedicated tile uses home', () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final app = AppState.demo(
        repository: DemoRepository(auth: auth),
        auth: auth,
      );
      addTearDown(app.dispose);
      await pumpEventQueue();

      final saved = await app.saveFanProfile(
        name: 'Fan',
        bio: null,
        homeLocation: FanCity.berkeley,
        genres: const [],
        locationPersonalizationEnabled: true,
        followedBandUpdatesEnabled: true,
      );

      expect(saved, isTrue);
      expect(
        discoveryLocationForFanCity(FanCity.berkeley),
        DiscoveryLocation.home,
      );

      app.selectFanCity(FanCity.berkeley);

      expect(app.discoveryLocation, DiscoveryLocation.home);
      expect(app.discoveryHomeCity, FanCity.berkeley);
    });

    test('all advanced filters combine in one result set', () async {
      final venue = DemoData.venues['v1']!;
      final show = DemoData.gigs[1];
      final app = await _app();
      app.useCurrentPosition(venue.point);
      app.setDateRange(DateTimeRange(start: show.startsAt, end: show.startsAt));
      app.toggleGenre('surf');
      app.setPriceFilter(PriceFilter.paid);
      app.setVenueFilter(venue.id);
      app.setDistanceFilter(1);

      expect(app.feed.map((gig) => gig.id), ['g2']);
    });

    test('location failures preserve the selected city', () async {
      final app = await _app(
        locationService: _FakeLocationService(
          const LocationFailure(LocationFailureReason.permissionDenied),
        ),
      );

      expect(await app.selectCurrentLocation(), isFalse);

      expect(app.discoveryLocation, DiscoveryLocation.sf);
      expect(app.currentPosition, isNull);
      expect(
        app.locationFailure?.reason,
        LocationFailureReason.permissionDenied,
      );
    });

    test('a late GPS result cannot override a newer manual city', () async {
      final location = _DeferredLocationService();
      final app = await _app(locationService: location);

      final pendingSelection = app.selectCurrentLocation();
      expect(app.locating, isTrue);
      app.setCity('oak');
      location.complete(
        const UserLocation(
          latitude: 37.7524,
          longitude: -122.4180,
          accuracyMeters: 5,
        ),
      );

      expect(await pendingSelection, isFalse);
      expect(app.locating, isFalse);
      expect(app.discoveryLocation, DiscoveryLocation.oak);
      expect(app.currentPosition, isNull);
    });

    test('widened ranges stay within the date picker horizon', () async {
      final app = await _app();
      final lastDate = app.lastSelectableDiscoveryDate;
      app.setDateRange(
        DateTimeRange(
          start: DateTime(lastDate.year, lastDate.month, lastDate.day - 2),
          end: lastDate,
        ),
      );

      app.widenDateFilter();

      expect(app.fDateRange!.end, lastDate);
      expect(
        app.fDateRange!.start.isBefore(app.firstSelectableDiscoveryDate),
        isFalse,
      );
    });

    test(
      'clear all preserves location and the intentional view switch',
      () async {
        final venue = DemoData.venues['v1']!;
        final app = await _app();
        app.useCurrentPosition(venue.point);
        app.setMapMode(false);
        app.toggleDateFilter(DateFilter.tonight);
        app.toggleGenre('punk');
        app.setPriceFilter(PriceFilter.paid);
        app.setVenueFilter('v1');
        app.setDistanceFilter(5);

        app.clearDiscoveryFilters();

        expect(app.filters.activeCount, 0);
        expect(app.discoveryLocation, DiscoveryLocation.current);
        expect(app.currentPosition, venue.point);
        expect(app.mapMode, isFalse);
      },
    );
  });
}

void _expectLabelsFollowDistanceOrder(AppState app) {
  final displayed = [
    for (final gig in app.feed)
      double.parse(app.distanceOf(app.venue(gig.venueId)).split(' ').first),
  ];
  expect(displayed, orderedEquals([...displayed]..sort()));
}

Future<AppState> _app({
  LocationService? locationService,
  DateTime? nextFeedStartsAt,
  List<Gig>? feedGigs,
}) async {
  final auth = FakeAuthService();
  final app = AppState.demo(
    repository: nextFeedStartsAt == null && feedGigs == null
        ? DemoRepository(auth: auth)
        : _BoundedFeedRepository(
            auth: auth,
            gigs: feedGigs ?? DemoData.gigs,
            nextStartsAt: nextFeedStartsAt,
          ),
    auth: auth,
    locationService: locationService,
  );
  addTearDown(app.dispose);
  await pumpEventQueue();
  return app;
}

class _BoundedFeedRepository extends DemoRepository {
  _BoundedFeedRepository({
    required super.auth,
    required this.gigs,
    required this.nextStartsAt,
  });

  final List<Gig> gigs;
  final DateTime? nextStartsAt;

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(
      gigs: gigs,
      venues: DemoData.venues,
      bands: DemoData.bands,
      nextStartsAt: nextStartsAt,
    ),
  );
}

class _FakeLocationService implements LocationService {
  const _FakeLocationService(this.result);

  final LocationResult result;

  @override
  Future<LocationResult> requestCurrentLocation() async => result;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _DeferredLocationService implements LocationService {
  final _result = Completer<LocationResult>();

  void complete(UserLocation location) {
    _result.complete(LocationSuccess(location));
  }

  @override
  Future<LocationResult> requestCurrentLocation() => _result.future;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}
