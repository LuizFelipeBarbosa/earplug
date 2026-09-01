import 'dart:convert';

import 'package:earplug/services/stadia_map_style_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('uses the correct endpoints and credential for both styles', () async {
    final client = _StyleClient();
    final providers = <_TrackingProvider>[];
    final repository = StadiaMapStyleRepository(
      apiKey: 'scoped-key',
      httpClient: client,
      cacheStyleBundles: false,
      resolveProvider: (_) async {
        final provider = _TrackingProvider();
        providers.add(provider);
        return provider;
      },
    );

    final firstLight = await repository.load(Brightness.light);
    final secondLight = await repository.load(Brightness.light);
    final dark = await repository.load(Brightness.dark);

    expect(identical(firstLight, secondLight), isTrue);
    expect(dark, isNot(same(firstLight)));
    expect(
      client.requests.map((request) => request.url.path),
      containsAll([
        '/styles/alidade_smooth.json',
        '/styles/alidade_smooth_dark.json',
      ]),
    );
    expect(
      client.requests,
      everyElement(
        isA<http.BaseRequest>().having(
          (request) => request.url.queryParameters['api_key'],
          'api_key',
          'scoped-key',
        ),
      ),
    );
    expect(client.requests, hasLength(2));

    repository.dispose();
    expect(providers, everyElement(isA<_TrackingProvider>()));
    expect(providers.every((provider) => provider.disposed), isTrue);
    expect(client.closed, isFalse, reason: 'Injected clients are caller-owned');
  });

  test(
    'prefetches the opposite style and retry invalidates one cache',
    () async {
      final client = _StyleClient();
      final providers = <_TrackingProvider>[];
      final repository = StadiaMapStyleRepository(
        apiKey: 'test-key',
        httpClient: client,
        cacheStyleBundles: false,
        resolveProvider: (_) async {
          final provider = _TrackingProvider();
          providers.add(provider);
          return provider;
        },
      );

      final firstLight = await repository.load(Brightness.light);
      await repository.load(Brightness.dark);
      expect(client.requests, hasLength(2));

      repository.retry(Brightness.light);
      expect(providers.first.disposed, isTrue);
      final retriedLight = await repository.load(Brightness.light);

      expect(retriedLight, isNot(same(firstLight)));
      expect(
        client.requests
            .where(
              (request) => request.url.path.endsWith('alidade_smooth.json'),
            )
            .length,
        2,
      );
      expect(
        client.requests
            .where(
              (request) =>
                  request.url.path.endsWith('alidade_smooth_dark.json'),
            )
            .length,
        1,
      );

      repository.dispose();
      expect(providers.every((provider) => provider.disposed), isTrue);
      expect(repository.load(Brightness.light), throwsA(isA<StateError>()));
    },
  );

  test('missing native credentials are a recoverable configuration error', () {
    final repository = StadiaMapStyleRepository(
      httpClient: _StyleClient(),
      cacheStyleBundles: false,
    );
    addTearDown(repository.dispose);

    expect(
      repository.load(Brightness.light),
      throwsA(isA<MapStyleConfigurationException>()),
    );
  });
}

class _StyleClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final bytes = utf8.encode(
      jsonEncode({
        'version': 8,
        'name': 'Test style',
        'sources': {
          'openmaptiles': {
            'type': 'vector',
            'tiles': ['https://tiles.test/{z}/{x}/{y}.pbf'],
            'attribution':
                '<a href="https://stadiamaps.com/">© Stadia Maps</a> '
                '<a href="https://openmaptiles.org/">© OpenMapTiles</a> '
                '<a href="https://www.openstreetmap.org/copyright">© OpenStreetMap</a>',
          },
        },
        'layers': [
          {
            'id': 'background',
            'type': 'background',
            'paint': {'background-color': '#101114'},
          },
        ],
      }),
    );
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  @override
  void close() => closed = true;
}

class _TrackingProvider extends vt.VectorTileProvider {
  bool disposed = false;

  @override
  bool get cacheBytesToDisk => false;

  @override
  String get cacheKey => 'tracking-provider-${identityHashCode(this)}';

  @override
  int get maximumZoom => 14;

  @override
  int get minimumZoom => 0;

  @override
  Future<vt.TileResponse> load(
    vt.TileKey tile, {
    vt.CancellationToken? cancellation,
  }) async => const vt.TileResponseNotFound();

  @override
  void dispose() => disposed = true;
}
