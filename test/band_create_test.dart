import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_identity_editor.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

void main() {
  testWidgets('create uses the shared identity editor in profile order', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pump();

    expect(findUiText('CREATE BAND'), findsWidgets);
    expect(find.byType(BandIdentityHeader), findsNothing);
    expect(find.byKey(const ValueKey('create-about')), findsNothing);
    await openAllFormSections(tester);
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
    expect(about.dy, lessThan(profile.dy));
    expect(name.dy, lessThan(area.dy));
    expect(area.dy, lessThan(genres.dy));
    expect(genres.dy, lessThan(about.dy));

    for (final key in const [
      ValueKey('create-band-name'),
      ValueKey('create-home-base'),
      ValueKey('create-about'),
    ]) {
      final field = tester.widget<TextField>(find.byKey(key));
      final decoration = field.decoration!.applyDefaults(
        Theme.of(tester.element(find.byKey(key))).inputDecorationTheme,
      );
      expect(decoration.enabledBorder, isA<OutlineInputBorder>());
      expect(field.style?.fontSize, 16);
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
    expect(findUiText('MANAGE VIDEOS AND PHOTOS'), findsNothing);

    harness.picker.nextPhoto = photoFixture(filename: 'banner.png');
    await revealFormKey(tester, const ValueKey('band-header-image-control'));
    await tester.tap(find.byKey(const ValueKey('band-header-image-control')));
    await tester.pumpAndSettle();
    expect(harness.app.nbBanner, isNotNull);
    expect(harness.app.nbPhoto, isNull);

    harness.picker.nextPhoto = photoFixture(filename: 'avatar.png');
    await revealFormKey(tester, const ValueKey('band-profile-image-control'));
    await tester.tap(find.byKey(const ValueKey('band-profile-image-control')));
    await tester.pumpAndSettle();
    expect(harness.app.nbPhoto, isNotNull);
    expect(harness.app.nbBanner?.filename, 'banner.png');

    expect(find.byKey(const ValueKey('clear-band-photo')), findsOne);
    expect(find.byKey(const ValueKey('clear-band-banner')), findsOne);
    await revealFormKey(tester, const ValueKey('clear-band-photo'));
    await tester.tap(find.byKey(const ValueKey('clear-band-photo')));
    await tester.pump();
    expect(harness.app.nbPhoto, isNull);
    expect(find.byKey(const ValueKey('clear-band-photo')), findsNothing);
    expect(find.byKey(const ValueKey('clear-band-banner')), findsOne);

    await revealFormKey(tester, const ValueKey('clear-band-banner'));

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

    await chooseBandGenres(tester, ['punk', 'hardcore', 'garage']);
    await tester.pump();
    expect(harness.app.nbGenres, ['punk', 'hardcore', 'garage']);

    await chooseBandGenres(tester, ['hardcore']);
    await revealFormKey(tester, const ValueKey('show-custom-genre'));
    await tester.tap(find.byKey(const ValueKey('show-custom-genre')));
    await tester.pump();
    await revealFormKey(tester, const ValueKey('edit-custom-genre'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-custom-genre')),
      'surf punk',
    );
    await tester.tap(findUiControl(FilledButton, 'ADD'));
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

    await chooseBandGenres(tester, ['punk', 'hardcore', 'garage']);
    await revealFormKey(tester, const ValueKey('show-custom-genre'));
    await tester.tap(find.byKey(const ValueKey('show-custom-genre')));
    await tester.pump();
    final customGenre = find.byKey(const ValueKey('edit-custom-genre'));
    await tester.enterText(customGenre, 'ska');
    await tester.tap(findUiControl(FilledButton, 'ADD'));
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
    await revealFormKey(tester, const ValueKey('band-header-image-control'));
    await tester.tap(find.byKey(const ValueKey('band-header-image-control')));
    await tester.pumpAndSettle();
    harness.picker.nextPhoto = photoFixture(filename: 'avatar.png');
    await revealFormKey(tester, const ValueKey('band-profile-image-control'));
    await tester.tap(find.byKey(const ValueKey('band-profile-image-control')));
    await tester.pumpAndSettle();

    await _fillForm(tester);
    await tester.tap(findUiControl(FilledButton, 'CREATE BAND'));
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

    expect(findUiText("YOU'RE LIVE"), findsOne);
    expect(findUiText('POST A MUSIC CLIP'), findsOne);
    expect(findUiText('PUBLISH A GIG'), findsOne);
    expect(findUiText('INVITE BAND MEMBERS'), findsOne);
    expect(findUiText('NOT NOW'), findsOne);
    await tester.tap(findUiText('NOT NOW'));
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
    await revealFormKey(tester, const ValueKey('create-about'));
    await tester.enterText(
      find.byKey(const ValueKey('create-about')),
      'Signal-heavy post-punk.',
    );
    await revealFormKey(tester, const ValueKey('create-instagram'));
    await tester.enterText(
      find.byKey(const ValueKey('create-instagram')),
      '@staticbloom',
    );
    await revealFormKey(tester, const ValueKey('create-bandcamp'));
    await tester.enterText(
      find.byKey(const ValueKey('create-bandcamp')),
      'staticbloom.bandcamp.com',
    );
    await revealFormKey(tester, const ValueKey('create-youtube'));
    await tester.enterText(
      find.byKey(const ValueKey('create-youtube')),
      'youtube.com/@staticbloom',
    );
    await revealFormKey(tester, const ValueKey('create-credits'));
    await tester.enterText(
      find.byKey(const ValueKey('create-credits')),
      'Recorded by June.',
    );
    await tester.tap(findUiControl(FilledButton, 'CREATE BAND'));
    await tester.pumpAndSettle();
    expect(findUiText("YOU'RE LIVE"), findsOne);

    await tester.tap(findUiText('START ANOTHER'));
    await tester.pumpAndSettle();

    expect(harness.app.nbCreated, isFalse);
    expect(harness.app.canCreateBand, isFalse);
    expect(harness.app.nbGenres, isEmpty);
    expect(find.text('Static Bloom'), findsNothing);
    expect(find.text('Choose at least one genre.'), findsNothing);
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
        tester
            .widget<TextField>(find.byKey(key, skipOffstage: false))
            .controller!
            .text,
        isEmpty,
      );
    }
    expect(find.text('0 of 3 selected'), findsOne);
  });

  testWidgets('the create bar goes pending while the save is in flight', (
    tester,
  ) async {
    final repository = _GatedDemoRepository(auth: FakeAuthService());
    final createGate = repository.createGate;
    final app = (await _pumpBandCreate(tester, repository: repository)).app;
    await _fillForm(tester);

    await tester.tap(findUiControl(FilledButton, 'CREATE BAND'));
    await tester.pump();
    expect(findUiText('SAVING…'), findsOne);
    expect(repository.createCalls, 1);

    createGate.complete();
    await tester.pumpAndSettle();
    expect(app.nbCreated, isTrue);
    expect(findUiText("YOU'RE LIVE"), findsOne);
  });

  testWidgets(
    'created band is usable before membership subscription catches up',
    (tester) async {
      final repository = StubRepository(auth: FakeAuthService())
        ..returns('createBand', (
          band: const Band(
            id: 'silent-band',
            name: 'Static Bloom',
            genres: ['punk'],
            area: 'Mission, SF',
            color: Color(0xFF8FE6C4),
            initials: 'SB',
            followers: 1,
            bio: '',
            linkIg: null,
            linkBc: null,
            linkYt: null,
            credits: null,
          ),
          slug: 'static-bloom',
        ));
      final app = (await _pumpBandCreate(tester, repository: repository)).app;
      await _fillAndCreate(tester);

      expect(app.bandId, 'silent-band');
      expect(app.myBand?.name, 'Static Bloom');
      expect(app.myBands, contains('silent-band'));
      expect(app.roleFor('silent-band'), 'admin');
    },
  );

  testWidgets('an unready create reveals required fields without submitting', (
    tester,
  ) async {
    final app = (await _pumpBandCreate(tester)).app;
    final disabledCreate = tester.widget<FilledButton>(
      findUiControl(FilledButton, 'CREATE BAND'),
    );
    expect(disabledCreate.onPressed, isNotNull);
    await tester.tap(findUiControl(FilledButton, 'Create band'));
    await tester.pumpAndSettle();
    expect(find.text('Enter band name.'), findsOneWidget);
    expect(find.text('Choose at least one genre.'), findsOneWidget);
    expect(app.nbCreated, isFalse);
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
  await revealFormKey(tester, const ValueKey('create-band-name'));
  await tester.enterText(
    find.byKey(const ValueKey('create-band-name')),
    'Static Bloom',
  );
  await revealFormKey(tester, const ValueKey('create-home-base'));
  await tester.enterText(
    find.byKey(const ValueKey('create-home-base')),
    'Mission, SF',
  );
  await chooseBandGenres(tester, ['punk']);
}

Future<void> _fillAndCreate(WidgetTester tester) async {
  await _fillForm(tester);
  await tester.tap(findUiControl(FilledButton, 'CREATE BAND'));
  await tester.pumpAndSettle();
}

class _GatedDemoRepository extends StubRepository {
  _GatedDemoRepository({required super.auth});

  late final createGate = gate('createBand');
  int get createCalls => callsTo('createBand');
}
