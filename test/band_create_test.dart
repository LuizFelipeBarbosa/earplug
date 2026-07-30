import 'dart:async';
import 'dart:convert';

import 'package:earplug/app_state.dart';
import 'package:earplug/band_media_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/screens/band_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/media_picker.dart';
import 'package:earplug/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('the tape, its labels and every sheet render and drive the form',
      (tester) async {
    final app = (await _pumpBandCreate(tester)).app;

    // Header, blank cassette and the liner notes.
    expect(find.text('START A BAND'), findsOne);
    expect(find.text('DRAFT'), findsOne);
    expect(find.text('SIDE A · DEMO'), findsOne);
    expect(find.text('HOME TAPING'), findsOne);
    expect(find.text('what do you sound like?'), findsOne);
    expect(find.text('BAND NAME · REQUIRED'), findsOne);
    expect(find.text('SOUND · REQUIRED'), findsOne);
    expect(find.text('HOME BASE · REQUIRED'), findsOne);
    expect(find.text('TAPE FILLS AS YOU GO'), findsOne);
    expect(find.text('0%'), findsOne);
    expect(
      find.text('Still needs a name + a genre + a home base'),
      findsOne,
    );

    // Writing on the tape label fills the liner-notes line below it too.
    await tester.enterText(find.byType(TextField).first, 'Static Bloom');
    await tester.pump();
    expect(app.nbName, 'Static Bloom');
    expect(find.text('BAND NAME ✓'), findsOne);
    expect(find.text('earplug.app/static-bloom'), findsOne);
    expect(find.text('20%'), findsOne);

    await tester.tap(find.byKey(const ValueKey('label-riso')));
    await tester.pump();
    expect(app.nbLabel, 'riso');

    // Sound sheet — chips cap at three, plus one of your own.
    await tester.tap(find.text('SOUND · REQUIRED'));
    await tester.pumpAndSettle();
    expect(find.text('Up to three — this is what fans filter by.'), findsOne);
    await tester.tap(find.text('PUNK'));
    await tester.tap(find.text('HARDCORE'));
    await tester.tap(find.text('GARAGE'));
    await tester.pump();
    await tester.tap(find.text('THRASH'));
    await tester.pump();
    expect(app.nbGenres, ['punk', 'hardcore', 'garage']);
    expect(app.toast, 'Three genres max — it keeps discovery honest.');
    await tester.tap(find.text('HARDCORE'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Something else…'),
      'surf punk',
    );
    await tester.tap(find.text('ADD'));
    await tester.pump();
    expect(app.nbGenres, ['punk', 'garage', 'surf punk']);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.text('punk · garage · surf punk'), findsOne);
    expect(find.text('SOUND ✓'), findsOne);

    // Home base sheet — the scene picks come with band and venue counts.
    await tester.tap(find.text('HOME BASE · REQUIRED'));
    await tester.pumpAndSettle();
    expect(find.text('Fans browsing nearby see you first.'), findsOne);
    expect(find.textContaining('venue'), findsWidgets);
    await tester.tap(find.text('MISSION, SF'));
    await tester.pumpAndSettle();
    expect(app.nbArea, 'Mission, SF');
    expect(find.text('MISSION, SF'), findsOne); // the tape stamp
    expect(find.text('READY'), findsOne);
    expect(
      find.text('Ready — you can post a gig the moment this lands.'),
      findsOne,
    );

    // The lower liner notes sit under the create bar until scrolled clear.
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();

    // Sleeve notes sheet — the starter line fills the bio.
    await tester.tap(find.text('SLEEVE NOTES'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USE A STARTER LINE'));
    await tester.pump();
    expect(app.nbBio, isNotEmpty);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.text('SLEEVE NOTES ✓'), findsOne);

    // Credits sheet — invite a bandmate, then change your mind.
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREDITS'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '@username'),
      'mara.k',
    );
    await tester.tap(find.text('INVITE'));
    await tester.pump();
    expect(app.nbInvites, ['@mara.k']);
    expect(find.text('INVITED'), findsOne);
    // No join link to copy yet — the slug it would use isn't real until the
    // server issues one, and this name is about to be deduped.
    expect(find.text('COPY LINK'), findsNothing);
    expect(
      find.text(
        'Your join link lands with the tape. Invites you add now go out the '
        'moment it does.',
      ),
      findsOne,
    );
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    expect(app.nbInvites, isEmpty);
    // With the invite row gone, the last close icon is the sheet's own ✕.
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    // Links sheet.
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LINKS'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '@yourband'),
      '@staticbloom',
    );
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(app.nbIg, '@staticbloom');
    expect(find.text('Instagram'), findsOne);
    // Links fill the fifth liner line, so the tape is fully wound.
    expect(find.text('FULL TAPE'), findsOne);
    expect(find.text('100%'), findsOne);

    // Create, then the tape's-out confirmation.
    await tester.tap(find.text('CREATE BAND'));
    await tester.pumpAndSettle();
    expect(app.nbCreated, isTrue);
    expect(find.text("TAPE'S OUT"), findsOne);
    expect(find.text("You're on the map."), findsOne);
    // The demo feed already has a Static Bloom, so the server-issued slug
    // dedupes.
    expect(find.text('earplug.app/static-bloom-2'), findsOne);
    expect(app.myBand!.name, 'Static Bloom');
    expect(app.myBand!.area, 'Mission, SF');

    await tester.tap(find.text('START ANOTHER'));
    await tester.pumpAndSettle();
    expect(app.nbName, isEmpty);
    expect(find.text('DRAFT'), findsOne);
    expect(find.text('HOME TAPING'), findsOne);

    // Let the genre-cap toast expire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the created view leads out three ways', (tester) async {
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);

    // The header ✕ is gone on this screen, so a plain exit has to live here.
    expect(find.text('GO TO BAND'), findsOne);
    await tester.tap(find.text('GO TO BAND'));
    await tester.pumpAndSettle();
    expect(app.current.screen, Screen.bandDash);
  });

  testWidgets('the join link becomes copyable once the slug is real',
      (tester) async {
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);

    // Back into the form with the band already landed.
    await tester.tap(find.text('KEEP EDITING'));
    await tester.pumpAndSettle();
    expect(find.text('SAVE CHANGES'), findsOne);

    await tester.drag(find.byType(ListView), const Offset(0, -560));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREDITS'));
    await tester.pumpAndSettle();

    // Now it is the server's slug, and it can be copied.
    expect(find.text('COPY LINK'), findsOne);
    expect(find.text('earplug.app/join/${app.nbShareSlug}'), findsOne);
    expect(app.nbShareSlug, 'static-bloom-2');
  });

  testWidgets('the create bar goes pending while the save is in flight',
      (tester) async {
    final repository = _GatedDemoRepository(auth: FakeAuthService());
    final app =
        (await _pumpBandCreate(tester, repository: repository)).app;
    await _fillForm(tester);

    await tester.tap(find.text('CREATE BAND'));
    await tester.pump();
    // Visibly pending rather than silently blocked.
    expect(find.text('SAVING…'), findsOne);
    expect(find.text('CREATE BAND'), findsNothing);

    // Tapping again while pending must not queue a second band.
    await tester.tap(find.text('SAVING…'));
    await tester.pump();
    expect(repository.createCalls, 1);

    repository.gate.complete();
    await tester.pumpAndSettle();
    expect(app.nbCreated, isTrue);
    expect(find.text("TAPE'S OUT"), findsOne);
  });

  testWidgets('the photo slot picks and clears an inlay behind the tape',
      (tester) async {
    final harness = await _pumpBandCreate(tester);
    final app = harness.app;
    harness.picker.nextPhoto = _photoFixture();
    expect(find.text('DROP A BAND PHOTO'), findsOne);

    await tester.tap(find.byKey(const ValueKey('label-photo')));
    await tester.pumpAndSettle();
    expect(app.nbPhoto, isNotNull);
    expect(find.byType(Image), findsOne);
    expect(find.byIcon(Icons.check), findsOne);
    expect(find.text('DROP A BAND PHOTO'), findsNothing);
    expect(
      find.text('Photo sits behind the tape — drop one in above.'),
      findsOne,
    );

    await tester.tap(find.byKey(const ValueKey('clear-band-photo')));
    await tester.pump();
    expect(app.nbPhoto, isNull);
    expect(find.text('DROP A BAND PHOTO'), findsOne);
    expect(find.byIcon(Icons.arrow_upward), findsOne);
  });

  testWidgets('a picked band photo lands as the first gallery hero',
      (tester) async {
    final harness = await _pumpBandCreate(tester);
    harness.picker.nextPhoto = _photoFixture();

    await tester.tap(find.byKey(const ValueKey('label-photo')));
    await tester.pumpAndSettle();
    await _fillForm(tester);
    await tester.tap(find.text('CREATE BAND'));
    await tester.pumpAndSettle();

    final bandId = harness.app.bandId;
    await harness.controller.refresh(bandId);
    final photos = harness.controller.photosFor(bandId);
    expect(photos, hasLength(1));
    expect(photos.single.isHero, isTrue);
  });

  testWidgets('an unready create explains itself instead of firing',
      (tester) async {
    final app = (await _pumpBandCreate(tester)).app;

    await tester.tap(find.text('CREATE BAND'));
    await tester.pump();
    expect(app.nbCreated, isFalse);
    expect(
      app.toast,
      'Add a name + a genre + a home base first — tap any line.',
    );

    // Let the toast expire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));
  });
}

Future<({AppState app, BandMediaController controller, FakeMediaPicker picker})>
    _pumpBandCreate(
  WidgetTester tester, {
  EarplugRepository? repository,
  FakeMediaPicker? picker,
}) async {
  // A phone-sized surface: the design targets 402x874.
  tester.view.physicalSize = const Size(402, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = FakeAuthService();
  final app = AppState(
    repository: repository ?? DemoRepository(auth: auth),
    auth: auth,
  );
  addTearDown(app.dispose);
  await tester.pumpAndSettle();
  final resolvedPicker = picker ?? FakeMediaPicker();
  final controller = BandMediaController(
    repository: app.repository,
    picker: resolvedPicker,
    say: app.say,
  );
  app.attachMediaController(controller);
  addTearDown(controller.dispose);
  app.startBandCreate();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: controller),
      ],
      child: MaterialApp(
        theme: buildEpTheme(),
        home: const Scaffold(body: BandCreateScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (app: app, controller: controller, picker: resolvedPicker);
}

PickedMedia _photoFixture() {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  return PickedMedia(
    bytes: bytes,
    filename: 'band_photo.png',
    contentType: 'image/png',
    sizeBytes: bytes.lengthInBytes,
  );
}

/// Fills the three required lines through the UI, leaving the bar ready.
Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'Static Bloom');
  await tester.pump();

  await tester.tap(find.text('SOUND · REQUIRED'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('PUNK'));
  await tester.pump();
  await tester.tap(find.text('DONE'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('HOME BASE · REQUIRED'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('MISSION, SF'));
  await tester.pumpAndSettle();
}

Future<void> _fillAndCreate(WidgetTester tester) async {
  await _fillForm(tester);
  await tester.tap(find.text('CREATE BAND'));
  await tester.pumpAndSettle();
}

/// A demo repository whose create only lands when the test opens the gate.
class _GatedDemoRepository extends DemoRepository {
  _GatedDemoRepository({required super.auth});

  final gate = Completer<void>();
  int createCalls = 0;

  @override
  Future<({String bandId, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required List<String> inviteHandles,
    String? area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
  }) async {
    createCalls++;
    await gate.future;
    return super.createBand(
      name: name,
      genres: genres,
      bio: bio,
      inviteHandles: inviteHandles,
      area: area,
      linkIg: linkIg,
      linkBc: linkBc,
      linkYt: linkYt,
    );
  }
}

class FakeMediaPicker implements MediaPicker {
  PickedMedia? nextPhoto;
  List<PickedMedia> nextPhotos = [];
  PickedMedia? nextVideo;
  MediaPickException? nextException;

  @override
  Future<PickedMedia?> pickPhoto() async {
    _throwIfNeeded();
    return nextPhoto;
  }

  @override
  Future<({List<PickedMedia> photos, List<String> oversized})> pickPhotos({
    int limit = 10,
  }) async {
    _throwIfNeeded();
    return (photos: nextPhotos, oversized: const <String>[]);
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    _throwIfNeeded();
    return nextVideo;
  }

  void _throwIfNeeded() {
    final error = nextException;
    if (error != null) throw error;
  }
}
