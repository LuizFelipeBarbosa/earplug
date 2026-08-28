import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  testWidgets('the tape, its labels and every sheet render and drive the form', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    final app = harness.app;
    harness.picker.nextPhoto = photoFixture();

    // Header, blank cassette and task-oriented profile details.
    expect(find.text('START A BAND'), findsOne);
    expect(find.text('DRAFT'), findsOne);
    expect(find.text('SIDE A · SAMPLE'), findsOne);
    expect(find.text('SET HOME BASE'), findsOne);
    expect(find.text('what do you sound like?'), findsOne);
    expect(find.text('BAND NAME · REQUIRED'), findsOne);
    expect(find.text('SOUND · REQUIRED'), findsOne);
    expect(find.text('HOME BASE · REQUIRED'), findsOne);
    expect(find.text('PROFILE DETAILS'), findsOne);
    expect(find.text('Required details'), findsOne);
    expect(find.text('TAPE FILLS AS YOU GO'), findsOne);
    expect(find.text('0%'), findsOne);
    expect(find.text('Still needs a name + a genre + a home base'), findsOne);

    // The standard name field updates the decorative cassette preview.
    await tester.enterText(find.byType(TextField).first, 'Static Bloom');
    await tester.pump();
    expect(app.nbName, 'Static Bloom');
    expect(find.text('BAND NAME ✓'), findsOne);
    expect(find.text('earplug.dev/static-bloom'), findsOne);
    expect(find.text('17%'), findsOne);

    await tester.tap(find.byKey(const ValueKey('label-riso')));
    await tester.pump();
    expect(app.nbLabel, 'riso');

    // Sound sheet — chips cap at three, plus one of your own.
    await tester.ensureVisible(find.text('SOUND · REQUIRED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SOUND · REQUIRED'));
    await tester.pumpAndSettle();
    expect(
      find.text('Choose up to three. Fans use these to find you.'),
      findsOne,
    );
    await tester.tap(find.text('PUNK'));
    await tester.tap(find.text('HARDCORE'));
    await tester.tap(find.text('GARAGE'));
    await tester.pump();
    await tester.tap(find.text('THRASH'));
    await tester.pump();
    expect(app.nbGenres, ['punk', 'hardcore', 'garage']);
    expect(app.toast, 'Three genres max. It keeps discovery honest.');
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
    expect(find.text('PUNK · GARAGE · SURF PUNK'), findsOne);
    expect(find.text('SOUND ✓'), findsOne);

    // Home base sheet — the scene picks come with band and venue counts.
    await tester.ensureVisible(find.text('HOME BASE · REQUIRED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HOME BASE · REQUIRED'));
    await tester.pumpAndSettle();
    expect(find.text('Fans browsing nearby see you first.'), findsOne);
    expect(find.textContaining('venue'), findsWidgets);
    await tester.tap(find.text('MISSION, SF'));
    await tester.pumpAndSettle();
    expect(app.nbArea, 'Mission, SF');
    expect(find.text('HOME BASE ✓'), findsOne);
    expect(find.text('READY'), findsOne);
    expect(
      find.text('Ready. Profile image, short bio, and links can wait.'),
      findsOne,
    );

    // The lower profile details sit under the create bar until scrolled clear.
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();

    // The optional profile image is part of the same visible checklist.
    await tester.tap(find.text('PROFILE IMAGE · OPTIONAL'));
    await tester.pumpAndSettle();
    expect(app.nbPhoto, isNotNull);
    expect(find.text('PROFILE IMAGE ✓'), findsOne);

    // Short bio sheet: the starter line fills the profile copy.
    await tester.tap(find.text('SHORT BIO · OPTIONAL'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USE A STARTER LINE'));
    await tester.pump();
    expect(app.nbBio, isNotEmpty);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.text('SHORT BIO ✓'), findsOne);

    // Credits are free text and remain separate from member invitations.
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CREDITS · OPTIONAL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('create-credits')),
      'Recorded by Mara K.',
    );
    await tester.pump();
    expect(app.nbCredits, 'Recorded by Mara K.');
    expect(find.widgetWithText(TextField, '@username'), findsNothing);
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.text('CREDITS ✓'), findsOne);

    // Links sheet.
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LINKS · OPTIONAL'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '@yourband'),
      '@staticbloom',
    );
    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(app.nbIg, '@staticbloom');
    expect(find.text('Instagram'), findsOne);
    // All six profile checklist steps are now complete.
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();
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
    expect(find.text('earplug.dev/static-bloom-2'), findsOne);
    expect(app.myBand!.name, 'Static Bloom');
    expect(app.myBand!.area, 'Mission, SF');

    await tester.tap(find.text('START ANOTHER'));
    await tester.pumpAndSettle();
    expect(app.nbName, isEmpty);
    expect(find.text('DRAFT'), findsOne);
    expect(find.text('SET HOME BASE'), findsOne);

    // Let the genre-cap toast expire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the created view offers next steps and a clear not-now exit', (
    tester,
  ) async {
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);

    expect(find.text('POST A MUSIC CLIP'), findsOne);
    expect(find.text('PUBLISH A GIG'), findsOne);
    expect(find.text('NOT NOW'), findsOne);
    await tester.tap(find.text('NOT NOW'));
    await tester.pumpAndSettle();
    expect(app.current.screen, Screen.bandDash);
  });

  testWidgets('the created view opens the music clip workflow', (tester) async {
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);

    await tester.tap(find.text('POST A MUSIC CLIP'));
    await tester.pump();

    expect(app.current.screen, Screen.bandMedia);
  });

  testWidgets('the created view opens the gig publishing workflow', (
    tester,
  ) async {
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);

    await tester.tap(find.text('PUBLISH A GIG'));
    await tester.pump();

    expect(app.current.screen, Screen.gigCreate);
  });

  testWidgets('member invitations are only available after creation', (
    tester,
  ) async {
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);

    await tester.tap(find.text('INVITE BAND MEMBERS'));
    await tester.pump();
    expect(app.current.screen, Screen.bandEdit);
    expect(app.current.param, 'members');
  });

  testWidgets('the create bar goes pending while the save is in flight', (
    tester,
  ) async {
    final repository = _GatedDemoRepository(auth: FakeAuthService());
    final app = (await _pumpBandCreate(tester, repository: repository)).app;
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

  testWidgets('the photo slot picks and clears an inlay behind the tape', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    final app = harness.app;
    harness.picker.nextPhoto = photoFixture();
    expect(find.text('BAND PHOTO PREVIEW'), findsOne);

    await tester.tap(find.byKey(const ValueKey('label-photo')));
    await tester.pumpAndSettle();
    expect(app.nbPhoto, isNotNull);
    expect(find.byType(Image), findsOne);
    expect(find.byIcon(Icons.check), findsOne);
    expect(find.text('BAND PHOTO PREVIEW'), findsNothing);
    expect(find.text('Photo sits behind the tape as a preview.'), findsOne);

    await tester.tap(find.byKey(const ValueKey('clear-band-photo')));
    await tester.pump();
    expect(app.nbPhoto, isNull);
    expect(find.text('BAND PHOTO PREVIEW'), findsOne);
    expect(find.byIcon(Icons.arrow_upward), findsOne);
  });

  testWidgets('a picked band photo lands as the first gallery hero', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    harness.picker.nextPhoto = photoFixture();

    await tester.tap(find.byKey(const ValueKey('label-photo')));
    await tester.pumpAndSettle();
    await _fillForm(tester);
    await tester.tap(find.text('CREATE BAND'));
    await tester.pumpAndSettle();

    final bandId = harness.app.bandId;
    await harness.media.refresh(bandId);
    final photos = harness.media.photosFor(bandId);
    expect(photos, hasLength(1));
    expect(photos.single.isHero, isTrue);
  });

  testWidgets(
    'created band is usable before membership subscription catches up',
    (tester) async {
      final repository = _SilentCreateRepository(auth: FakeAuthService());
      final app = (await _pumpBandCreate(tester, repository: repository)).app;

      await _fillAndCreate(tester);

      expect(app.bandId, 'silent-band');
      expect(app.myBand?.name, 'Static Bloom');
      expect(app.myBands, contains('silent-band'));
      expect(app.roleFor('silent-band'), 'admin');
      expect(app.isAdminOf('silent-band'), isTrue);
    },
  );

  testWidgets('an unready create is visibly and semantically disabled', (
    tester,
  ) async {
    final app = (await _pumpBandCreate(tester)).app;

    final disabledCreate = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'CREATE BAND'),
    );
    expect(disabledCreate.onPressed, isNull);
    expect(app.nbCreated, isFalse);
  });
}

Future<AppHarness> _pumpBandCreate(
  WidgetTester tester, {
  EarplugRepository? repository,
}) => pumpApp(
  tester,
  repository: repository,
  // Let the demo streams land before the form opens, the way they have by the
  // time a real user reaches this screen.
  beforePump: (app) async {
    await tester.pumpAndSettle();
    app.startBandCreate();
  },
  home: const Scaffold(body: BandCreateScreen()),
);

/// Fills the three required lines through the UI, leaving the bar ready.
Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'Static Bloom');
  await tester.pump();

  final sound = find.text('SOUND · REQUIRED');
  await tester.ensureVisible(sound);
  await tester.pumpAndSettle();
  await tester.tap(sound);
  await tester.pumpAndSettle();
  await tester.tap(find.text('PUNK'));
  await tester.pump();
  await tester.tap(find.text('DONE'));
  await tester.pumpAndSettle();

  final homeBase = find.text('HOME BASE · REQUIRED');
  await tester.ensureVisible(homeBase);
  await tester.pumpAndSettle();
  await tester.tap(homeBase);
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
  Future<({Band band, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required String area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
  }) async {
    createCalls++;
    await gate.future;
    return super.createBand(
      name: name,
      genres: genres,
      bio: bio,
      area: area,
      linkIg: linkIg,
      linkBc: linkBc,
      linkYt: linkYt,
      credits: credits,
    );
  }
}

/// Returns the mutation payload without publishing a matching myBands event,
/// reproducing the short websocket lag that can follow a live create.
class _SilentCreateRepository extends DemoRepository {
  _SilentCreateRepository({required super.auth});

  @override
  Future<({Band band, String slug})> createBand({
    required String name,
    required List<String> genres,
    required String bio,
    required String area,
    String? linkIg,
    String? linkBc,
    String? linkYt,
    String? credits,
  }) async => (
    band: Band(
      id: 'silent-band',
      name: name,
      genres: genres,
      area: area,
      color: const Color(0xFF8FE6C4),
      initials: 'SB',
      followers: 1,
      bio: bio,
      linkIg: linkIg,
      linkBc: linkBc,
      linkYt: linkYt,
      credits: credits,
    ),
    slug: 'static-bloom',
  );
}
