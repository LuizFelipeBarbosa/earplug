import 'dart:async';
import 'dart:convert';

import 'package:earplug/app_state.dart';
import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/services/appearance_controller.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:earplug/services/stadia_map_style_repository.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

/// Everything [pumpApp] wired up, for the test to drive and assert against.
class AppHarness {
  const AppHarness({
    required this.app,
    required this.auth,
    required this.media,
    required this.picker,
  });

  final AppState app;
  final FakeAuthService auth;
  final BandMediaController media;
  final FakeMediaPicker picker;
}

/// Pumps [home] the way main.dart hosts a screen: an [AppState] and a
/// [BandMediaController] provided above a themed [MaterialApp], on a
/// phone-sized surface, all disposed at teardown.
///
/// Pass [auth] when the test needs to hold the same service the state and the
/// [repository] share; leave [repository] null for plain demo data.
/// [beforePump] runs against the wired-up state before the first frame — use it
/// for whatever the screen expects to already be in flight. [pumpFor] advances
/// a fixed duration instead of settling, for screens that hold a timer open.
Future<AppHarness> pumpApp(
  WidgetTester tester, {
  required Widget home,
  FakeAuthService? auth,
  EarplugRepository? repository,
  MediaUploadService? uploader,
  LocationService? locationService,
  DateTime Function()? now,
  FutureOr<void> Function(AppState app)? beforePump,
  Duration? pumpFor,
}) async {
  // A phone-sized surface: the design targets 402x874.
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final resolvedAuth = auth ?? FakeAuthService();
  final resolvedRepository = repository ?? DemoRepository(auth: resolvedAuth);
  final resolvedUploader =
      uploader ??
      MediaUploadService(
        repository: resolvedRepository,
        thumbnailGenerator: FakeVideoThumbnailGenerator(),
      );
  final app = AppState(
    repository: resolvedRepository,
    auth: resolvedAuth,
    locationService: locationService,
    mediaUploadService: resolvedUploader,
    now: now,
  );

  final picker = FakeMediaPicker();
  final media = BandMediaController(
    repository: resolvedRepository,
    picker: picker,
    uploader: resolvedUploader,
    say: app.say,
  );
  app.attachMediaController(media);
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final appearance = await AppearanceController.load();
  addTearDown(appearance.dispose);
  final mapClient = MockClient((request) async {
    if (request.url.path.endsWith('.json')) {
      return http.Response(
        jsonEncode({
          'version': 8,
          'name': 'EarPlug test map',
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
    }
    return http.Response.bytes(const [], 200);
  });
  final mapStyles = StadiaMapStyleRepository(
    apiKey: 'test-key',
    httpClient: mapClient,
    cacheStyleBundles: false,
    resolveProvider: (_) async => _EmptyVectorTileProvider(),
  );
  addTearDown(() {
    mapStyles.dispose();
    mapClient.close();
  });

  await beforePump?.call(app);

  await tester.pumpWidget(
    MultiProvider(
      key: UniqueKey(),
      providers: [
        ChangeNotifierProvider<AppState>(create: (_) => app),
        ChangeNotifierProvider<AppearanceController>.value(value: appearance),
        Provider<StadiaMapStyleRepository>.value(value: mapStyles),
        ChangeNotifierProvider<BandMediaController>(create: (_) => media),
      ],
      child: MaterialApp(theme: buildEpTheme(), home: home),
    ),
  );
  if (pumpFor == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(pumpFor);
  }

  return AppHarness(app: app, auth: resolvedAuth, media: media, picker: picker);
}

class _EmptyVectorTileProvider extends vt.VectorTileProvider {
  @override
  bool get cacheBytesToDisk => false;

  @override
  String get cacheKey => 'earplug-test-map';

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
