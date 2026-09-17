import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/geocoding_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/discovery_app.dart';

void main() {
  group('app state location', () {
    test('manual city selection prioritizes the nearest scene', () async {
      final app = await discoveryApp();

      expect(app.feed.first.venueId, 'v1');
      expectLabelsFollowDistanceOrder(app);
      app.setCity('oak');

      expect(app.feed.first.venueId, 'v2');
      expectLabelsFollowDistanceOrder(app);
    });

    test(
      'GPS distance uses venue coordinates and manual city clears it',
      () async {
        final venue = DemoData.venues['v1']!;
        final location = FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: venue.point.latitude,
              longitude: venue.point.longitude,
              accuracyMeters: 5,
            ),
          ),
        );
        final app = await discoveryApp(locationService: location);

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

    test('Use my location turns on with a successful foreground fix', () async {
      final venue = DemoData.venues['v1']!;
      final app = await discoveryApp(
        locationService: FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: venue.point.latitude,
              longitude: venue.point.longitude,
              accuracyMeters: 5,
            ),
          ),
        ),
      );

      expect(await app.setUseCurrentLocation(true), isTrue);
      expect(app.discoveryLocation, DiscoveryLocation.current);
      expect(app.usingCurrentLocation, isTrue);
    });

    test('reverse geocoding updates the current location label', () async {
      final venue = DemoData.venues['v1']!;
      final app = await discoveryApp(
        locationService: FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: venue.point.latitude,
              longitude: venue.point.longitude,
              accuracyMeters: 5,
            ),
          ),
        ),
        reverseGeocoding: const FakeReverseGeocoding(
          PlaceName(neighbourhood: 'Temescal', locality: 'Oakland'),
        ),
      );

      await app.setUseCurrentLocation(true);
      await pumpEventQueue();

      expect(app.locationLabel, 'TEMESCAL, OAKLAND');
    });

    test('stale reverse geocoding does not change the scene label', () async {
      final venue = DemoData.venues['v1']!;
      final reverse = DeferredReverseGeocoding();
      final app = await discoveryApp(
        locationService: FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: venue.point.latitude,
              longitude: venue.point.longitude,
              accuracyMeters: 5,
            ),
          ),
        ),
        reverseGeocoding: reverse,
      );

      await app.setUseCurrentLocation(true);
      await app.setUseCurrentLocation(false);
      reverse.complete(
        const PlaceName(neighbourhood: 'Mission', locality: 'SF'),
      );
      await pumpEventQueue();

      expect(app.locationLabel, 'MISSION, SF');
    });

    test('current location falls back without reverse geocoding', () async {
      final venue = DemoData.venues['v1']!;
      final app = await discoveryApp(
        locationService: FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: venue.point.latitude,
              longitude: venue.point.longitude,
              accuracyMeters: 5,
            ),
          ),
        ),
      );

      await app.setUseCurrentLocation(true);

      expect(app.locationLabel, 'CURRENT LOCATION');
    });

    test('Use my location turns off to the saved home scene', () async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      final app = AppState.demo(
        repository: DemoRepository(auth: auth),
        auth: auth,
        locationService: const FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: 37.7524,
              longitude: -122.4180,
              accuracyMeters: 5,
            ),
          ),
        ),
      );
      addTearDown(app.dispose);
      await pumpEventQueue();

      expect(
        await app.saveFanProfile(
          name: 'Fan',
          bio: null,
          homeLocation: FanCity.berkeley,
          genres: const [],
          locationPersonalizationEnabled: true,
          followedBandUpdatesEnabled: true,
        ),
        isTrue,
      );

      await app.setUseCurrentLocation(true);
      await app.setUseCurrentLocation(false);

      expect(app.discoveryLocation, DiscoveryLocation.home);
      expect(app.locationLabel, 'BERKELEY SCENE');
    });

    test('Use my location turns off to Mission without a profile', () async {
      final app = await discoveryApp(
        locationService: const FakeLocationService(
          LocationSuccess(
            UserLocation(
              latitude: 37.7524,
              longitude: -122.4180,
              accuracyMeters: 5,
            ),
          ),
        ),
      );

      await app.setUseCurrentLocation(true);
      await app.setUseCurrentLocation(false);

      expect(app.discoveryLocation, DiscoveryLocation.sf);
    });

    test(
      'turning Use my location off cancels a pending GPS response',
      () async {
        final location = DeferredLocationService();
        final app = await discoveryApp(locationService: location);

        final pendingSelection = app.setUseCurrentLocation(true);
        expect(app.locating, isTrue);
        expect(await app.setUseCurrentLocation(false), isTrue);
        expect(app.discoveryLocation, DiscoveryLocation.sf);
        expect(app.locating, isFalse);

        location.complete(
          const UserLocation(
            latitude: 37.7524,
            longitude: -122.4180,
            accuracyMeters: 5,
          ),
        );

        expect(await pendingSelection, isFalse);
        expect(app.discoveryLocation, DiscoveryLocation.sf);
        expect(app.currentPosition, isNull);
      },
    );

    test(
      'dismissLocationFailure clears the current location failure',
      () async {
        final app = await discoveryApp(
          locationService: const FakeLocationService(
            LocationFailure(LocationFailureReason.permissionDenied),
          ),
        );

        expect(await app.setUseCurrentLocation(true), isFalse);
        expect(app.locationFailure, isNotNull);

        app.dismissLocationFailure();

        expect(app.locationFailure, isNull);
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

    test('location failures preserve the selected city', () async {
      final app = await discoveryApp(
        locationService: const FakeLocationService(
          LocationFailure(LocationFailureReason.permissionDenied),
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
      final location = DeferredLocationService();
      final app = await discoveryApp(locationService: location);

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
  });
}
