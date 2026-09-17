import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/geocoding_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'stub_repository.dart';

/// Builds a demo [AppState] for discovery tests and disposes it on tear down.
///
/// Passing [nextFeedStartsAt] or [feedGigs] swaps the demo repository for a
/// [StubRepository] whose feed snapshot carries those values.
Future<AppState> discoveryApp({
  LocationService? locationService,
  ReverseGeocodingService? reverseGeocoding,
  DateTime? nextFeedStartsAt,
  List<Gig>? feedGigs,
}) async {
  final auth = FakeAuthService();
  final app = AppState.demo(
    repository: nextFeedStartsAt == null && feedGigs == null
        ? DemoRepository(auth: auth)
        : (StubRepository(auth: auth)..returnsStream(
            'feed',
            () => Stream.value(
              FeedSnapshot(
                gigs: feedGigs ?? DemoData.gigs,
                venues: DemoData.venues,
                bands: DemoData.bands,
                nextStartsAt: nextFeedStartsAt,
              ),
            ),
          )),
    auth: auth,
    locationService: locationService,
    reverseGeocoding: reverseGeocoding,
  );
  addTearDown(app.dispose);
  await pumpEventQueue();
  return app;
}

/// Asserts the feed's displayed distance labels are in ascending order.
void expectLabelsFollowDistanceOrder(AppState app) {
  final displayed = [
    for (final gig in app.feed)
      double.parse(app.distanceOf(app.venue(gig.venueId)).split(' ').first),
  ];
  expect(displayed, orderedEquals([...displayed]..sort()));
}

class FakeLocationService implements LocationService {
  const FakeLocationService(this.result);

  final LocationResult result;

  @override
  Future<LocationResult> requestCurrentLocation() async => result;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class DeferredLocationService implements LocationService {
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

class FakeReverseGeocoding implements ReverseGeocodingService {
  const FakeReverseGeocoding(this.place);

  final PlaceName place;

  @override
  Future<PlaceName?> reverseGeocode(LatLng point) async => place;
}

class DeferredReverseGeocoding implements ReverseGeocodingService {
  final _result = Completer<PlaceName?>();

  void complete(PlaceName place) => _result.complete(place);

  @override
  Future<PlaceName?> reverseGeocode(LatLng point) => _result.future;
}
