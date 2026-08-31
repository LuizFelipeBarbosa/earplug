import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// A geographic position returned by [LocationService].
///
/// Keeping this type independent from geolocator lets application state and
/// widget tests provide locations without depending on a platform plugin.
class UserLocation {
  const UserLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
}

sealed class LocationResult {
  const LocationResult();
}

final class LocationSuccess extends LocationResult {
  const LocationSuccess(this.location);

  final UserLocation location;
}

enum LocationFailureReason {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

final class LocationFailure extends LocationResult {
  const LocationFailure(this.reason, {this.message});

  final LocationFailureReason reason;
  final String? message;
}

abstract interface class LocationService {
  /// Requests a single foreground location.
  ///
  /// Implementations must not prompt for permission until this method is
  /// called in response to an explicit user action.
  Future<LocationResult> requestCurrentLocation();

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorLocationService implements LocationService {
  factory GeolocatorLocationService({
    GeolocatorPlatform? platform,
    Duration requestDeadline = const Duration(seconds: 20),
  }) => GeolocatorLocationService._(
    platform ?? GeolocatorPlatform.instance,
    requestDeadline,
  );

  GeolocatorLocationService._(this._platform, this._requestDeadline);

  static const LocationSettings _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 15),
  );
  final GeolocatorPlatform _platform;
  final Duration _requestDeadline;

  @override
  Future<LocationResult> requestCurrentLocation() async {
    try {
      return await _requestCurrentLocation().timeout(_requestDeadline);
    } on TimeoutException {
      return const LocationFailure(
        LocationFailureReason.unavailable,
        message: 'Location request timed out. Retry or choose a city.',
      );
    } catch (error) {
      return LocationFailure(
        LocationFailureReason.unavailable,
        message: error.toString(),
      );
    }
  }

  Future<LocationResult> _requestCurrentLocation() async {
    try {
      final servicesEnabled = await _platform.isLocationServiceEnabled();
      if (!servicesEnabled) {
        return const LocationFailure(LocationFailureReason.servicesDisabled);
      }

      var permission = await _platform.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return const LocationFailure(LocationFailureReason.permissionDenied);
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationFailure(
          LocationFailureReason.permissionDeniedForever,
        );
      }

      final position = await _platform.getCurrentPosition(
        locationSettings: _settings,
      );
      return LocationSuccess(
        UserLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
        ),
      );
    } on LocationServiceDisabledException {
      return const LocationFailure(LocationFailureReason.servicesDisabled);
    } on TimeoutException catch (error) {
      return LocationFailure(
        LocationFailureReason.unavailable,
        message: error.message,
      );
    } catch (error) {
      return LocationFailure(
        LocationFailureReason.unavailable,
        message: error.toString(),
      );
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await _platform.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await _platform.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}

double distanceInMiles({
  required double startLatitude,
  required double startLongitude,
  required double endLatitude,
  required double endLongitude,
}) {
  const metersPerMile = 1609.344;
  final meters = Geolocator.distanceBetween(
    startLatitude,
    startLongitude,
    endLatitude,
    endLongitude,
  );
  return meters / metersPerMile;
}
