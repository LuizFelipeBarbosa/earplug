import 'dart:async';
import 'dart:convert';

import 'package:earplug/services/stadia_map_style_repository.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('blocks taps while loading and renders linked attribution', (
    tester,
  ) async {
    final responseGate = Completer<void>();
    final client = MockClient((_) async {
      await responseGate.future;
      return _styleResponse();
    });
    final repository = _repository(client);
    addTearDown(repository.dispose);
    var taps = 0;

    await tester.pumpWidget(
      _mapHost(
        repository,
        EpMap(
          options: MapOptions(
            initialCenter: const LatLng(34.05, -118.24),
            initialZoom: 12,
            onTap: (_, _) => taps++,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Loading map'), findsOne);
    await tester.tapAt(const Offset(100, 200));
    expect(taps, 0);

    responseGate.complete();
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Loading map'), findsNothing);
    expect(find.text('© Stadia Maps'), findsOne);
    expect(find.text('© OpenMapTiles'), findsOne);
    expect(find.text('© OpenStreetMap'), findsOne);
    final attributionLinks = tester.widgetList<InkWell>(find.byType(InkWell));
    expect(attributionLinks.where((link) => link.onTap != null), hasLength(3));
    expect(
      tester
          .widget<AbsorbPointer>(find.byKey(const Key('map-input-blocker')))
          .absorbing,
      isFalse,
    );
  });

  testWidgets('shows a recoverable map error and retries in place', (
    tester,
  ) async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      return attempts == 1
          ? http.Response('unavailable', 503)
          : _styleResponse();
    });
    final repository = _repository(client);
    addTearDown(repository.dispose);

    await tester.pumpWidget(
      _mapHost(
        repository,
        const EpMap(
          options: MapOptions(
            initialCenter: LatLng(34.05, -118.24),
            initialZoom: 12,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MAP UNAVAILABLE'), findsOne);
    expect(tester.getSize(find.widgetWithText(TextButton, 'RETRY')).height, 48);

    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();

    expect(find.text('MAP UNAVAILABLE'), findsNothing);
    expect(find.text('© Stadia Maps'), findsOne);
  });

  testWidgets('switching ready styles preserves the map camera', (
    tester,
  ) async {
    final client = MockClient((_) async => _styleResponse());
    final repository = _repository(client);
    addTearDown(repository.dispose);
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    final controller = MapController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      Provider.value(
        value: repository,
        child: ValueListenableBuilder(
          valueListenable: brightness,
          builder: (context, value, _) => MaterialApp(
            theme: buildEpTheme(value),
            home: Scaffold(
              body: EpMap(
                mapController: controller,
                options: const MapOptions(
                  initialCenter: LatLng(34.05, -118.24),
                  initialZoom: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    const moved = LatLng(34.14, -118.19);
    controller.move(moved, 14);
    await tester.pump();

    brightness.value = Brightness.dark;
    await tester.pumpAndSettle();

    expect(controller.camera.center.latitude, closeTo(moved.latitude, .0001));
    expect(controller.camera.center.longitude, closeTo(moved.longitude, .0001));
    expect(controller.camera.zoom, closeTo(14, .01));
  });
}

StadiaMapStyleRepository _repository(http.Client client) {
  return StadiaMapStyleRepository(
    apiKey: 'test-key',
    httpClient: client,
    cacheStyleBundles: false,
    resolveProvider: (_) async => _EmptyVectorTileProvider(),
  );
}

Widget _mapHost(StadiaMapStyleRepository repository, Widget child) {
  return Provider.value(
    value: repository,
    child: MaterialApp(
      theme: buildEpTheme(Brightness.light),
      home: Scaffold(body: child),
    ),
  );
}

http.Response _styleResponse() => http.Response(
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
  200,
  headers: {'content-type': 'application/json'},
);

class _EmptyVectorTileProvider extends vt.VectorTileProvider {
  @override
  bool get cacheBytesToDisk => false;

  @override
  String get cacheKey => 'ep-map-test-${identityHashCode(this)}';

  @override
  int get maximumZoom => 14;

  @override
  int get minimumZoom => 0;

  @override
  Future<vt.TileResponse> load(
    vt.TileKey tile, {
    vt.CancellationToken? cancellation,
  }) async => const vt.TileResponseNotFound();
}
