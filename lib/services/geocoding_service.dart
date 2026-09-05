import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class AddressSuggestion {
  const AddressSuggestion({
    required this.label,
    required this.address,
    required this.area,
    this.locality,
    this.region,
    this.postalCode,
    required this.point,
  });

  final String label;
  final String address;
  final String area;
  final String? locality;
  final String? region;
  final String? postalCode;
  final LatLng point;
}

sealed class GeocodingFailure implements Exception {
  const GeocodingFailure();
}

class GeocodingUnauthorized extends GeocodingFailure {
  const GeocodingUnauthorized();
}

class GeocodingRateLimited extends GeocodingFailure {
  const GeocodingRateLimited();
}

class GeocodingNetworkFailure extends GeocodingFailure {
  const GeocodingNetworkFailure();
}

class GeocodingMalformed extends GeocodingFailure {
  const GeocodingMalformed();
}

abstract interface class GeocodingService {
  Future<List<AddressSuggestion>> autocomplete(String text, {LatLng? focus});
}

class StadiaGeocodingService implements GeocodingService {
  StadiaGeocodingService({
    this.apiKey = '',
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 6),
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  final String apiKey;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<List<AddressSuggestion>> autocomplete(
    String text, {
    LatLng? focus,
  }) async {
    final uri = buildUri(text: text, focus: focus, apiKey: apiKey);
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const GeocodingNetworkFailure();
    } on http.ClientException {
      throw const GeocodingNetworkFailure();
    } catch (_) {
      throw const GeocodingNetworkFailure();
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GeocodingUnauthorized();
    }
    if (response.statusCode == 429) {
      throw const GeocodingRateLimited();
    }
    if (response.statusCode != 200) {
      throw const GeocodingMalformed();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const GeocodingMalformed();
    }

    try {
      return parseFeatures(decoded);
    } catch (_) {
      throw const GeocodingMalformed();
    }
  }

  static Uri buildUri({
    required String text,
    LatLng? focus,
    required String apiKey,
  }) {
    final effectiveFocus = focus ?? const LatLng(37.7749, -122.4194);
    final params = <String, String>{
      'text': text,
      'size': '5',
      'layers': 'address,venue',
      'boundary.country': 'USA',
      'focus.point.lat': effectiveFocus.latitude.toString(),
      'focus.point.lon': effectiveFocus.longitude.toString(),
    };
    if (apiKey.isNotEmpty) params['api_key'] = apiKey;
    return Uri.parse(
      'https://api.stadiamaps.com/geocoding/v1/autocomplete',
    ).replace(queryParameters: params);
  }

  static List<AddressSuggestion> parseFeatures(Object? json) {
    if (json is! Map) {
      throw const FormatException('Expected a GeoJSON object.');
    }
    final features = json['features'];
    if (features is! List) {
      throw const FormatException('Expected a GeoJSON features list.');
    }

    final suggestions = <AddressSuggestion>[];
    for (final feature in features) {
      if (feature is! Map) continue;
      final geometry = feature['geometry'];
      final properties = feature['properties'];
      if (geometry is! Map || properties is! Map) continue;

      final coordinates = geometry['coordinates'];
      final label = _nonEmptyString(properties['label']);
      if (coordinates is! List || coordinates.length < 2 || label == null) {
        continue;
      }
      final longitude = coordinates[0];
      final latitude = coordinates[1];
      if (longitude is! num || latitude is! num) continue;

      final houseNumber = _nonEmptyString(properties['housenumber']);
      final street = _nonEmptyString(properties['street']);
      final neighbourhood = _nonEmptyString(properties['neighbourhood']);
      final locality = _nonEmptyString(properties['locality']);
      final region = _nonEmptyString(properties['region']);
      final postalCode = _nonEmptyString(properties['postalcode']);
      final address = houseNumber != null && street != null
          ? ['$houseNumber $street', ?locality, ?region, ?postalCode].join(', ')
          : label;

      suggestions.add(
        AddressSuggestion(
          label: label,
          address: address,
          area: neighbourhood ?? locality ?? region ?? '',
          locality: locality,
          region: region,
          postalCode: postalCode,
          point: LatLng(latitude.toDouble(), longitude.toDouble()),
        ),
      );
    }
    return suggestions;
  }

  static String? _nonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
