import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:earplug/services/media_upload_service.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

  await beforePump?.call(app);

  await tester.pumpWidget(
    MultiProvider(
      key: UniqueKey(),
      providers: [
        ChangeNotifierProvider<AppState>(create: (_) => app),
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
