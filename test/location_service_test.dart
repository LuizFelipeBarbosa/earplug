import 'package:earplug/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('location result types', () {
    test('success exposes an app-owned geographic position', () {
      const result = LocationSuccess(
        UserLocation(
          latitude: 37.7599,
          longitude: -122.4148,
          accuracyMeters: 12,
        ),
      );

      expect(result.location.latitude, 37.7599);
      expect(result.location.longitude, -122.4148);
      expect(result.location.accuracyMeters, 12);
    });

    test('failures distinguish every recovery path', () {
      expect(
        LocationFailureReason.values,
        containsAll(<LocationFailureReason>[
          LocationFailureReason.servicesDisabled,
          LocationFailureReason.permissionDenied,
          LocationFailureReason.permissionDeniedForever,
          LocationFailureReason.unavailable,
        ]),
      );
    });
  });

  test('distanceInMiles returns an appropriate nearby-event distance', () {
    final miles = distanceInMiles(
      startLatitude: 37.7599,
      startLongitude: -122.4148,
      endLatitude: 37.8044,
      endLongitude: -122.2712,
    );

    expect(miles, closeTo(8.4, 0.2));
  });

  group('GeolocatorLocationService', () {
    test('does not request permission when services are disabled', () async {
      final platform = _FakeGeolocatorPlatform()..servicesEnabled = false;
      final service = GeolocatorLocationService(platform: platform);

      final result = await service.requestCurrentLocation();

      expect(
        (result as LocationFailure).reason,
        LocationFailureReason.servicesDisabled,
      );
      expect(platform.permissionRequestCount, 0);
    });

    test(
      'requests permission only after the location request starts',
      () async {
        final platform = _FakeGeolocatorPlatform(
          checkedPermission: LocationPermission.denied,
          requestedPermission: LocationPermission.whileInUse,
        );
        final service = GeolocatorLocationService(platform: platform);

        expect(platform.permissionRequestCount, 0);

        final result = await service.requestCurrentLocation();

        expect(result, isA<LocationSuccess>());
        expect(platform.permissionRequestCount, 1);
      },
    );

    test('distinguishes denied and denied-forever permission', () async {
      final deniedPlatform = _FakeGeolocatorPlatform(
        checkedPermission: LocationPermission.denied,
        requestedPermission: LocationPermission.denied,
      );
      final deniedForeverPlatform = _FakeGeolocatorPlatform(
        checkedPermission: LocationPermission.deniedForever,
      );

      final denied = await GeolocatorLocationService(
        platform: deniedPlatform,
      ).requestCurrentLocation();
      final deniedForever = await GeolocatorLocationService(
        platform: deniedForeverPlatform,
      ).requestCurrentLocation();

      expect(
        (denied as LocationFailure).reason,
        LocationFailureReason.permissionDenied,
      );
      expect(
        (deniedForever as LocationFailure).reason,
        LocationFailureReason.permissionDeniedForever,
      );
      expect(deniedForeverPlatform.permissionRequestCount, 0);
    });

    test('maps a platform position to UserLocation', () async {
      final service = GeolocatorLocationService(
        platform: _FakeGeolocatorPlatform(),
      );

      final result = await service.requestCurrentLocation() as LocationSuccess;

      expect(result.location.latitude, 37.7599);
      expect(result.location.longitude, -122.4148);
      expect(result.location.accuracyMeters, 12);
    });

    test('maps unexpected platform errors to unavailable', () async {
      final platform = _FakeGeolocatorPlatform()
        ..positionError = StateError('No browser location');

      final result = await GeolocatorLocationService(
        platform: platform,
      ).requestCurrentLocation();

      expect(
        (result as LocationFailure).reason,
        LocationFailureReason.unavailable,
      );
      expect(result.message, contains('No browser location'));
    });

    test('settings actions safely report unsupported platforms', () async {
      final platform = _FakeGeolocatorPlatform()
        ..settingsError = UnsupportedError('Settings are unavailable');
      final service = GeolocatorLocationService(platform: platform);

      expect(await service.openAppSettings(), isFalse);
      expect(await service.openLocationSettings(), isFalse);
    });
  });
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({
    this.checkedPermission = LocationPermission.whileInUse,
    this.requestedPermission = LocationPermission.whileInUse,
  });

  bool servicesEnabled = true;
  LocationPermission checkedPermission;
  LocationPermission requestedPermission;
  int permissionRequestCount = 0;
  Object? positionError;
  Object? settingsError;

  @override
  Future<bool> isLocationServiceEnabled() async => servicesEnabled;

  @override
  Future<LocationPermission> checkPermission() async => checkedPermission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequestCount++;
    return requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final error = positionError;
    if (error != null) throw error;
    return Position(
      longitude: -122.4148,
      latitude: 37.7599,
      timestamp: DateTime(2026),
      accuracy: 12,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<bool> openAppSettings() async {
    final error = settingsError;
    if (error != null) throw error;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    final error = settingsError;
    if (error != null) throw error;
    return true;
  }
}
