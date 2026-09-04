import 'dart:convert';

import 'package:earplug/services/geocoding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() {
  group('parseFeatures', () {
    test(
      'parses Pelias fields, area precedence, and skips missing geometry',
      () {
        final suggestions = StadiaGeocodingService.parseFeatures({
          'type': 'FeatureCollection',
          'features': [
            {
              'geometry': {
                'type': 'Point',
                'coordinates': [-122.4220, 37.7676],
              },
              'properties': {
                'label': '22 Valencia St, San Francisco, CA, USA',
                'name': '22 Valencia Street',
                'housenumber': '22',
                'street': 'Valencia St',
                'neighbourhood': 'Mission',
                'locality': 'San Francisco',
                'region': 'CA',
                'postalcode': '94103',
              },
            },
            {
              'geometry': {
                'type': 'Point',
                'coordinates': [-122.2711, 37.8044],
              },
              'properties': {
                'label': 'Fox Theater, Oakland, CA, USA',
                'name': 'Fox Theater',
                'locality': 'Oakland',
                'region': 'CA',
              },
            },
            {
              'properties': {
                'label': 'Feature without geometry',
                'name': 'Missing Point',
              },
            },
          ],
        });

        expect(suggestions, hasLength(2));
        expect(suggestions.first.address, '22 Valencia St');
        expect(suggestions.first.area, 'Mission');
        expect(suggestions.first.locality, 'San Francisco');
        expect(suggestions.first.region, 'CA');
        expect(suggestions.first.postalCode, '94103');
        expect(suggestions.first.point, const LatLng(37.7676, -122.4220));
        expect(suggestions[1].address, 'Fox Theater');
        expect(suggestions[1].area, 'Oakland');
      },
    );
  });

  group('buildUri', () {
    test('includes an API key and explicit focus', () {
      final uri = StadiaGeocodingService.buildUri(
        text: 'Fox Theater',
        focus: const LatLng(37.8044, -122.2711),
        apiKey: 'secret-key',
      );

      expect(uri.queryParameters['api_key'], 'secret-key');
      expect(uri.queryParameters['focus.point.lat'], '37.8044');
      expect(uri.queryParameters['focus.point.lon'], '-122.2711');
      expect(uri.queryParameters['text'], 'Fox Theater');
    });

    test('omits an empty API key and uses the San Francisco focus', () {
      final uri = StadiaGeocodingService.buildUri(text: 'Valencia', apiKey: '');

      expect(uri.queryParameters, isNot(contains('api_key')));
      expect(uri.queryParameters['focus.point.lat'], '37.7749');
      expect(uri.queryParameters['focus.point.lon'], '-122.4194');
    });
  });

  group('autocomplete failures', () {
    test('maps HTTP 401 to GeocodingUnauthorized', () async {
      final service = StadiaGeocodingService(
        httpClient: _GeocodingClient(statusCode: 401),
      );

      await expectLater(
        service.autocomplete('Valencia'),
        throwsA(isA<GeocodingUnauthorized>()),
      );
    });

    test('maps HTTP 429 to GeocodingRateLimited', () async {
      final service = StadiaGeocodingService(
        httpClient: _GeocodingClient(statusCode: 429),
      );

      await expectLater(
        service.autocomplete('Valencia'),
        throwsA(isA<GeocodingRateLimited>()),
      );
    });

    test('maps malformed successful responses to GeocodingMalformed', () async {
      final service = StadiaGeocodingService(
        httpClient: _GeocodingClient(statusCode: 200, body: 'not json'),
      );

      await expectLater(
        service.autocomplete('Valencia'),
        throwsA(isA<GeocodingMalformed>()),
      );
    });
  });
}

class _GeocodingClient extends http.BaseClient {
  _GeocodingClient({required this.statusCode, this.body = ''});

  final int statusCode;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}
