import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_identity_editor.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accessibility.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  testWidgets('create uses the shared identity editor in profile order', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pump();

    expect(find.text('CREATE BAND'), findsWidgets);
    expect(find.byType(BandIdentityHeader), findsOne);
    expect(find.byKey(const ValueKey('band-header-image-control')), findsOne);
    expect(find.byKey(const ValueKey('band-profile-image-control')), findsOne);
    expect(find.bySemanticsLabel('Add profile image'), findsOne);
    expect(find.bySemanticsLabel('Add header image'), findsOne);

    final profile = tester.getTopLeft(
      find.byKey(const ValueKey('band-profile-image-control')),
    );
    final name = tester.getTopLeft(
      find.byKey(const ValueKey('create-band-name')),
    );
    final area = tester.getTopLeft(
      find.byKey(const ValueKey('create-home-base')),
    );
    final about = tester.getTopLeft(find.byKey(const ValueKey('create-about')));
    final genres = tester.getTopLeft(
      find.byKey(const ValueKey('band-genres-field')),
    );
    expect(profile.dy, lessThan(name.dy));
    expect(name.dy, lessThan(area.dy));
    expect(area.dy, lessThan(about.dy));
    expect(about.dy, lessThan(genres.dy));

    for (final key in const [
      ValueKey('create-band-name'),
      ValueKey('create-home-base'),
      ValueKey('create-about'),
    ]) {
      final field = tester.widget<TextField>(find.byKey(key));
      expect(field.decoration?.enabledBorder, isA<OutlineInputBorder>());
      expect(field.style?.fontSize, greaterThanOrEqualTo(18));
    }

    for (final key in const [
      ValueKey('create-instagram'),
      ValueKey('create-bandcamp'),
      ValueKey('create-youtube'),
    ]) {
      expect(
        find.ancestor(of: find.byKey(key), matching: find.byType(EpCard)),
        findsNothing,
      );
    }
    expect(find.text('MANAGE VIDEOS AND PHOTOS'), findsNothing);

    harness.picker.nextPhoto = photoFixture(filename: 'banner.png');
    await tester.tap(find.byKey(const ValueKey('band-header-image-control')));
    await tester.pumpAndSettle();
    expect(harness.app.nbBanner, isNotNull);
    expect(harness.app.nbPhoto, isNull);

    harness.picker.nextPhoto = photoFixture(filename: 'avatar.png');
    await tester.tap(find.byKey(const ValueKey('band-profile-image-control')));
    await tester.pumpAndSettle();
    expect(harness.app.nbPhoto, isNotNull);
    expect(harness.app.nbBanner?.filename, 'banner.png');

    expect(find.byKey(const ValueKey('clear-band-photo')), findsOne);
    expect(find.byKey(const ValueKey('clear-band-banner')), findsOne);
    await tester.tap(find.byKey(const ValueKey('clear-band-photo')));
    await tester.pump();
    expect(harness.app.nbPhoto, isNull);
    expect(find.byKey(const ValueKey('clear-band-photo')), findsNothing);
    expect(find.byKey(const ValueKey('clear-band-banner')), findsOne);

    await tester.tap(find.byKey(const ValueKey('clear-band-banner')));
    await tester.pump();
    expect(harness.app.nbBanner, isNull);
    expect(find.byKey(const ValueKey('clear-band-banner')), findsNothing);
    semantics.dispose();
  });

  testWidgets('create preserves genre validation and custom genre flow', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 2200);
    await tester.pump();

    await tester.tap(find.text('PUNK'));
    await tester.tap(find.text('HARDCORE'));
    await tester.tap(find.text('GARAGE'));
    await tester.tap(find.text('THRASH'));
    await tester.pump();
    expect(harness.app.nbGenres, ['punk', 'hardcore', 'garage']);
    expect(harness.app.toast, 'Three genres max. It keeps discovery honest.');

    await tester.tap(find.text('HARDCORE'));
    await tester.tap(find.byKey(const ValueKey('show-custom-genre')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('edit-custom-genre')),
      'surf punk',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ADD'));
    await tester.pump();
    expect(harness.app.nbGenres, ['punk', 'garage', 'surf punk']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('custom genre remains available when three are selected', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 2200);
    await tester.pump();

    await tester.tap(find.text('PUNK'));
    await tester.tap(find.text('HARDCORE'));
    await tester.tap(find.text('GARAGE'));
    await tester.tap(find.byKey(const ValueKey('show-custom-genre')));
    await tester.pump();
    final customGenre = find.byKey(const ValueKey('edit-custom-genre'));
    await tester.enterText(customGenre, 'ska');
    await tester.tap(find.widgetWithText(FilledButton, 'ADD'));
    await tester.pump();

    expect(harness.app.nbGenres, ['punk', 'hardcore', 'garage']);
    expect(harness.app.toast, 'Three genres max.');
    expect(customGenre, findsOne);
    expect(tester.widget<TextField>(customGenre).controller!.text, 'ska');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('avatar and banner upload into independent media roles', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 2200);
    await tester.pump();
    harness.picker.nextPhoto = photoFixture(filename: 'banner.png');
    await tester.tap(find.byKey(const ValueKey('band-header-image-control')));
    await tester.pumpAndSettle();
    harness.picker.nextPhoto = photoFixture(filename: 'avatar.png');
    await tester.tap(find.byKey(const ValueKey('band-profile-image-control')));
    await tester.pumpAndSettle();

    await _fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'CREATE BAND'));
    await tester.pumpAndSettle();

    final bandId = harness.app.bandId;
    await harness.media.refresh(bandId);
    final photos = harness.media.photosFor(bandId);
    expect(photos, hasLength(2));
    expect(photos.singleWhere((photo) => photo.isAvatar).title, 'AVATAR');
    expect(photos.singleWhere((photo) => photo.isBanner).title, 'BANNER');
  });

  testWidgets('created view keeps all established next steps', (tester) async {
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);

    expect(find.text("YOU'RE LIVE"), findsOne);
    expect(find.text('POST A MUSIC CLIP'), findsOne);
    expect(find.text('PUBLISH A GIG'), findsOne);
    expect(find.text('INVITE BAND MEMBERS'), findsOne);
    expect(find.text('NOT NOW'), findsOne);
    await tester.tap(find.text('NOT NOW'));
    await tester.pumpAndSettle();
    expect(app.current.screen, Screen.bandDash);
  });

  testWidgets('start another clears the rendered form and backing draft', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pumpAndSettle();

    await _fillForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey('create-about')),
      'Signal-heavy post-punk.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-instagram')),
      '@staticbloom',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-bandcamp')),
      'staticbloom.bandcamp.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-youtube')),
      'youtube.com/@staticbloom',
    );
    await tester.enterText(
      find.byKey(const ValueKey('create-credits')),
      'Recorded by June.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'CREATE BAND'));
    await tester.pumpAndSettle();
    expect(find.text("YOU'RE LIVE"), findsOne);

    await tester.tap(find.text('START ANOTHER'));
    await tester.pumpAndSettle();

    expect(harness.app.nbCreated, isFalse);
    expect(harness.app.canCreateBand, isFalse);
    expect(harness.app.nbGenres, isEmpty);
    expect(find.text('Static Bloom'), findsNothing);
    expect(find.text('Still needs a name + a genre + a home base'), findsOne);
    for (final key in const [
      ValueKey('create-band-name'),
      ValueKey('create-home-base'),
      ValueKey('create-about'),
      ValueKey('create-instagram'),
      ValueKey('create-bandcamp'),
      ValueKey('create-youtube'),
      ValueKey('create-credits'),
    ]) {
      expect(
        tester.widget<TextField>(find.byKey(key)).controller!.text,
        isEmpty,
      );
    }
    expect(
      tester.widget<EpChip>(find.widgetWithText(EpChip, 'PUNK')).active,
      isFalse,
    );
    expect(find.text('0 of 3 selected'), findsOne);
  });

  testWidgets('the create bar goes pending while the save is in flight', (
    tester,
  ) async {
    final repository = _GatedDemoRepository(auth: FakeAuthService());
    final app = (await _pumpBandCreate(tester, repository: repository)).app;
    await _fillForm(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'CREATE BAND'));
    await tester.pump();
    expect(find.text('SAVING…'), findsOne);
    expect(repository.createCalls, 1);

    repository.gate.complete();
    await tester.pumpAndSettle();
    expect(app.nbCreated, isTrue);
    expect(find.text("YOU'RE LIVE"), findsOne);
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

  testWidgets('band creation is usable at increased text scale', (
    tester,
  ) async {
    await pumpApp(
      tester,
      beforePump: (app) => app.startBandCreate(),
      home: scaledScreen(const BandCreateScreen()),
    );

    expect(find.text('CREATE BAND'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}

Future<AppHarness> _pumpBandCreate(
  WidgetTester tester, {
  EarplugRepository? repository,
}) {
  tester.view.devicePixelRatio = 1;
  return pumpApp(
    tester,
    repository: repository,
    beforePump: (app) async {
      await tester.pumpAndSettle();
      app.startBandCreate();
    },
    home: const Scaffold(body: BandCreateScreen()),
  );
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('create-band-name')),
    'Static Bloom',
  );
  await tester.enterText(
    find.byKey(const ValueKey('create-home-base')),
    'Mission, SF',
  );
  final punk = find.text('PUNK');
  await tester.scrollUntilVisible(
    punk,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(punk);
  await tester.pump();
}

Future<void> _fillAndCreate(WidgetTester tester) async {
  await _fillForm(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'CREATE BAND'));
  await tester.pumpAndSettle();
}

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
