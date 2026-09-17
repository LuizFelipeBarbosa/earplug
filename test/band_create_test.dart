import 'dart:ui' show Tristate;

import 'package:earplug/app_state.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_create.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/band_identity_editor.dart';
import 'package:earplug/widgets/brand_icons.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/genre_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/design_rules.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets(
    'create opens on the banner-only header, underline fields and a pinned create bar',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpBandCreate(tester);
      tester.view.physicalSize = const Size(402, 3000);
      await tester.pump();

      expect(find.text('CREATE BAND'), findsWidgets);
      expect(find.bySemanticsLabel('Back'), findsOne);
      expect(find.byKey(const ValueKey('band-create-back')), findsOne);

      // Banner-only header: no avatar editing anywhere on this screen.
      final header = tester.widget<BandIdentityHeader>(
        find.byType(BandIdentityHeader),
      );
      expect(header.showAvatar, isFalse);
      expect(header.onAvatarTap, isNull);
      expect(header.onBannerTap, isNotNull);
      final banner = find.byKey(const ValueKey('band-identity-header'));
      expect(banner, findsOne);
      expect(find.byKey(const ValueKey('band-header-image-control')), findsOne);
      expect(find.text('PROFILE IMAGE'), findsNothing);
      expect(
        find.byKey(const ValueKey('band-profile-image-control')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('band-profile-avatar-frame')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('Add profile image'), findsNothing);
      final bannerRect = tester.getRect(banner);
      expect(bannerRect.left, EpLayout.gutter);
      expect(bannerRect.width, 402 - 2 * EpLayout.gutter);
      expect(bannerRect.width / bannerRect.height, closeTo(2.65, .001));

      final change = find.byKey(const ValueKey('band-header-change'));
      expect(change, findsOne);
      expect(
        find.descendant(of: change, matching: find.text('Change')),
        findsOne,
      );
      expect(
        find.descendant(
          of: change,
          matching: find.byIcon(Icons.photo_camera_outlined),
        ),
        findsOne,
      );
      expect(find.text('Shown at the top of your public page.'), findsOne);
      expect(
        find.textContaining('Profile image and header image are separate'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('clear-band-photo')), findsNothing);
      expect(find.byKey(const ValueKey('clear-band-banner')), findsNothing);

      // Quiet underline identity fields with the ABOUT counter.
      expect(find.text('BAND NAME · REQUIRED'), findsOne);
      expect(find.bySemanticsLabel(RegExp(r'^BAND NAME · REQUIRED')), findsOne);
      expect(find.text('HOME BASE · REQUIRED'), findsOne);
      expect(find.bySemanticsLabel(RegExp(r'^HOME BASE · REQUIRED')), findsOne);
      expect(find.text('ABOUT'), findsOne);
      expect(find.bySemanticsLabel(RegExp(r'^ABOUT')), findsOne);
      expect(find.text('GENRES · REQUIRED'), findsOne);
      expect(find.text('LINKS'), findsOne);
      for (final key in const [
        ValueKey('create-band-name'),
        ValueKey('create-home-base'),
      ]) {
        expect(
          find.ancestor(
            of: find.byKey(key),
            matching: find.byType(EpUnderlineField),
          ),
          findsOne,
        );
        expect(tester.widget<TextField>(find.byKey(key)).style?.fontSize, 18);
      }
      final about = tester.widget<TextField>(
        find.byKey(const ValueKey('create-about')),
      );
      expect(about.maxLength, 160);
      expect(about.style?.fontSize, 18);
      expect(about.decoration!.enabledBorder, isA<UnderlineInputBorder>());
      expect(about.decoration!.helperText, isNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('create-short-bio-count')),
          matching: find.text('0 / 160'),
        ),
        findsOne,
      );

      // The same genres autocomplete as Edit Band: counter, no chip grid.
      final genreField = tester.widget<GenreAutocompleteField>(
        find.byType(GenreAutocompleteField),
      );
      expect(genreField.keyPrefix, 'edit-genres');
      expect(genreField.max, 3);
      expect(find.byType(BandGenreEditor), findsNothing);
      expect(find.byKey(const ValueKey('show-custom-genre')), findsNothing);
      expect(find.byKey(const ValueKey('edit-custom-genre')), findsNothing);
      expect(find.text('0 of 3 selected'), findsNothing);
      expect(
        tester
            .widget<EpMonoText>(find.byKey(const ValueKey('edit-genres-count')))
            .text,
        '0 OF 3',
      );

      // The same links block as Edit Band: one bordered surface with three
      // icon rows and platform hints, no descriptive paragraph.
      expect(
        find.textContaining('Add the places where fans can listen'),
        findsNothing,
      );
      expect(find.text('INSTAGRAM'), findsNothing);
      expect(find.text('YOUTUBE OR VIDEO'), findsNothing);
      final linksCard = _linksCard;
      expect(linksCard, findsOne);
      expect(
        find.descendant(of: linksCard, matching: find.byType(TextField)),
        findsNWidgets(3),
      );
      expect(
        find.descendant(of: linksCard, matching: find.byType(EpHairline)),
        findsNWidgets(2),
      );
      final glyphs = tester.widgetList<BrandIcon>(
        find.descendant(of: linksCard, matching: find.byType(BrandIcon)),
      );
      expect(glyphs.map((icon) => icon.glyph), [
        BrandGlyph.instagram,
        BrandGlyph.bandcamp,
        BrandGlyph.youtube,
      ]);
      final palette = tester.element(linksCard).epColors;
      expect(
        glyphs.every((icon) => icon.color == palette.contentSecondary),
        isTrue,
      );
      for (final (key, hint) in const [
        (ValueKey('create-instagram'), 'Instagram'),
        (ValueKey('create-bandcamp'), 'Bandcamp'),
        (ValueKey('create-youtube'), 'YouTube'),
      ]) {
        final field = find.byKey(key);
        expect(find.ancestor(of: field, matching: linksCard), findsOne);
        final decoration = tester.widget<TextField>(field).decoration!;
        expect(decoration.hintText, hint);
        expect(decoration.hintStyle?.color, palette.muted);
        expect(decoration.labelText, isNull);
        expect(decoration.border, InputBorder.none);
        expect(find.text(hint), findsOne);
      }

      // Nothing from the old form survives: credits, members, media rows.
      expect(find.text('CREDITS'), findsNothing);
      expect(find.byKey(const ValueKey('create-credits')), findsNothing);
      expect(find.text('INVITE BAND MEMBERS'), findsNothing);
      expect(find.text('MANAGE VIDEOS AND PHOTOS'), findsNothing);
      expect(find.byType(ReadyPill), findsNothing);
      expect(find.text('PREVIEW'), findsNothing);
      expect(find.byType(EpCard), findsNothing);
      expectNoFieldInCard(tester);

      final bannerTop = tester.getTopLeft(banner);
      final name = tester.getTopLeft(
        find.byKey(const ValueKey('create-band-name')),
      );
      final area = tester.getTopLeft(
        find.byKey(const ValueKey('create-home-base')),
      );
      final aboutTop = tester.getTopLeft(
        find.byKey(const ValueKey('create-about')),
      );
      final genres = tester.getTopLeft(
        find.byKey(const ValueKey('edit-genres-input')),
      );
      final links = tester.getTopLeft(linksCard);
      expect(bannerTop.dy, lessThan(name.dy));
      expect(name.dy, lessThan(area.dy));
      expect(area.dy, lessThan(aboutTop.dy));
      expect(aboutTop.dy, lessThan(genres.dy));
      expect(genres.dy, lessThan(links.dy));

      // Header row: back, title and the eye at the right edge, nothing else.
      final headerRow = find
          .ancestor(
            of: find.byKey(const ValueKey('band-create-back')),
            matching: find.byType(Row),
          )
          .first;
      expect(
        find.descendant(of: headerRow, matching: find.byType(EpPill)),
        findsNothing,
      );
      final eyeFinder = find.byKey(const ValueKey('band-create-preview'));
      expect(find.descendant(of: headerRow, matching: eyeFinder), findsOne);
      expect(tester.getRect(eyeFinder).right, 402 - EpLayout.gutter);
      // No draft preview exists before the band lands, so the eye waits.
      expect(tester.widget<EpIconPill>(eyeFinder).onPressed, isNull);
      expect(
        find.bySemanticsLabel('Preview available after creating'),
        findsOne,
      );

      // One pinned, full-width create bar with a single primary pill.
      final bar = find.byKey(const ValueKey('create-band-submit'));
      expect(bar, findsOne);
      expect(tester.widget(bar), isA<EpBottomCta>());
      final pill = tester.widget<EpPill>(_submitPill);
      expect(pill.label, 'Create band');
      expect(pill.variant, EpPillVariant.primary);
      expect(pill.size, EpPillSize.large);
      expect(pill.expand, isTrue);
      expect(pill.onPressed, isNull);
      expect(
        find.descendant(of: bar, matching: find.text('CREATE BAND')),
        findsOne,
      );
      expect(find.byType(FilledButton), findsNothing);
      final barRect = tester.getRect(bar);
      expect(barRect.left, 0);
      expect(barRect.width, 402);
      expect(barRect.bottom, 3000);
      final pillRect = tester.getRect(_submitPill);
      expect(pillRect.width, 402 - 2 * EpLayout.gutter);
      expect(pillRect.bottom, 3000 - 32);
      semantics.dispose();
    },
  );

  for (final inset in [34.0, 0.0]) {
    testWidgets('the create bar sits on the bottom safe inset ($inset)', (
      tester,
    ) async {
      await _pumpBandCreate(
        tester,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(402, 900),
            padding: EdgeInsets.only(bottom: inset),
          ),
          child: const Scaffold(body: BandCreateScreen()),
        ),
      );

      // No tab bar renders here, so the bar ends at the viewport's bottom
      // and lifts its pill above the inset (EpBottomCta pads 32 below it).
      final barRect = tester.getRect(
        find.byKey(const ValueKey('create-band-submit')),
      );
      expect(barRect.left, 0);
      expect(barRect.width, 402);
      expect(barRect.bottom, 900);
      final pillRect = tester.getRect(_submitPill);
      expect(pillRect.width, 402 - 2 * EpLayout.gutter);
      expect(pillRect.bottom, 900 - inset - 32);

      // The last form control scrolls clear of the pinned bar.
      final youtube = find.byKey(const ValueKey('create-youtube'));
      await tester.scrollUntilVisible(
        youtube,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(youtube).bottom, lessThanOrEqualTo(barRect.top));
      expect(youtube.hitTestable(), findsOne);
    });
  }

  testWidgets('about limits the bio and updates its live counter', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pump();

    final bio = find.byKey(const ValueKey('create-about'));
    expect(tester.widget<TextField>(bio).maxLength, 160);
    await tester.enterText(bio, 'A fresh band bio!!');
    await tester.pump();
    final counter = find.byKey(const ValueKey('create-short-bio-count'));
    expect(
      find.descendant(of: counter, matching: find.text('18 / 160')),
      findsOne,
    );
    expect(harness.app.nbBio, 'A fresh band bio!!');
    await tester.enterText(bio, 'Short');
    await tester.pump();
    expect(
      find.descendant(of: counter, matching: find.text('5 / 160')),
      findsOne,
    );
  });

  testWidgets('the header image is picked and cleared from its sheet', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('create-band-name')),
      'Static Bloom',
    );
    harness.picker.nextPhoto = photoFixture(filename: 'banner.png');
    await tester.tap(find.byKey(const ValueKey('band-header-change')));
    await tester.pumpAndSettle();
    expect(find.text('Replace'), findsOne);
    expect(find.text('Use initials instead'), findsNothing);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(harness.app.nbBanner?.filename, 'banner.png');
    expect(harness.app.nbPhoto, isNull);
    expect(
      tester
          .widget<BandIdentityHeader>(find.byType(BandIdentityHeader))
          .bannerBytes,
      isNotNull,
    );
    expect(harness.app.nbName, 'Static Bloom');

    await tester.tap(find.byKey(const ValueKey('band-header-image-control')));
    await tester.pumpAndSettle();
    expect(find.text('Replace'), findsOne);
    expect(find.text('Use initials instead'), findsOne);
    await tester.tap(find.text('Use initials instead'));
    await tester.pumpAndSettle();
    expect(harness.app.nbBanner, isNull);
    expect(
      tester
          .widget<BandIdentityHeader>(find.byType(BandIdentityHeader))
          .bannerBytes,
      isNull,
    );
    expect(find.text('SB'), findsOne);
    expect(harness.app.nbName, 'Static Bloom');
  });

  testWidgets(
    'genres use the shared autocomplete with suggestions, removal and custom entries',
    (tester) async {
      final harness = await _pumpBandCreate(tester);
      tester.view.physicalSize = const Size(402, 2200);
      await tester.pump();

      final input = find.byKey(const ValueKey('edit-genres-input'));
      final count = find.byKey(const ValueKey('edit-genres-count'));
      for (final (query, genre) in const [
        ('punk', 'punk'),
        ('hard', 'hardcore'),
        ('gar', 'garage'),
      ]) {
        await tester.enterText(input, query);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('edit-genres-suggestions')), findsOne);
        await tester.tap(
          find.byKey(const ValueKey('edit-genres-suggestion-0')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('edit-genres-chip-$genre')), findsOne);
      }
      expect(harness.app.nbGenres, ['punk', 'hardcore', 'garage']);
      expect(tester.widget<EpMonoText>(count).text, '3 OF 3');
      expect(tester.widget<TextField>(input).enabled, isFalse);
      expect(
        tester.widget<TextField>(input).decoration!.hintText,
        'Genres full',
      );
      expect(
        find.byKey(const ValueKey('edit-genres-suggestions')),
        findsNothing,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('edit-genres-chip-hardcore')),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(harness.app.nbGenres, ['punk', 'garage']);
      expect(
        find.byKey(const ValueKey('edit-genres-chip-hardcore')),
        findsNothing,
      );
      expect(tester.widget<EpMonoText>(count).text, '2 OF 3');
      expect(tester.widget<TextField>(input).enabled, isTrue);

      await tester.enterText(input, 'surf punk');
      await tester.pumpAndSettle();
      expect(find.text('Add "surf punk"'), findsOne);
      await tester.tap(find.byKey(const ValueKey('edit-genres-add-custom')));
      await tester.pumpAndSettle();
      expect(harness.app.nbGenres, ['punk', 'garage', 'surf punk']);
      expect(
        find.byKey(const ValueKey('edit-genres-chip-surf punk')),
        findsOne,
      );
      expect(tester.widget<EpMonoText>(count).text, '3 OF 3');
      expect(harness.app.toast, isEmpty);
    },
  );

  testWidgets('a fourth genre is refused inline without touching the draft', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 2200);
    await tester.pump();

    final input = find.byKey(const ValueKey('edit-genres-input'));
    for (final query in const ['punk', 'hard', 'gar']) {
      await tester.enterText(input, query);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-genres-suggestion-0')));
      await tester.pumpAndSettle();
    }
    expect(harness.app.nbGenres, ['punk', 'hardcore', 'garage']);
    expect(tester.widget<TextField>(input).enabled, isFalse);

    // A commit that lands after the last slot filled shows the limit note
    // where the user is looking instead of toasting.
    final field = tester.widget<TextField>(input);
    field.controller!.text = 'ska';
    field.onSubmitted!('ska');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-genres-limit')), findsOne);
    expect(find.text('Choose no more than three genres.'), findsOne);
    expect(harness.app.nbGenres, ['punk', 'hardcore', 'garage']);
    expect(harness.app.toast, isEmpty);
    expect(find.byKey(const ValueKey('edit-genres-chip-ska')), findsNothing);
  });

  testWidgets('a held header image uploads into the banner role on create', (
    tester,
  ) async {
    final harness = await _pumpBandCreate(tester);
    tester.view.physicalSize = const Size(402, 2200);
    await tester.pump();
    harness.picker.nextPhoto = photoFixture(filename: 'banner.png');
    await tester.tap(find.byKey(const ValueKey('band-header-change')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();

    await _fillForm(tester);
    await tester.tap(_submitPill);
    await tester.pumpAndSettle();

    final bandId = harness.app.bandId;
    await harness.media.refresh(bandId);
    final photos = harness.media.photosFor(bandId);
    expect(photos, hasLength(1));
    expect(photos.single.isBanner, isTrue);
    expect(photos.single.title, 'BANNER');
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
    expect(app.current.screen, Screen.gigMgr);
  });

  testWidgets('keep editing enables the preview eye for the landed band', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = (await _pumpBandCreate(tester)).app;
    await _fillAndCreate(tester);
    await tester.tap(find.text('KEEP EDITING'));
    await tester.pumpAndSettle();

    final eye = find.byKey(const ValueKey('band-create-preview'));
    expect(tester.widget<EpIconPill>(eye).onPressed, isNotNull);
    expect(find.bySemanticsLabel('Preview public page'), findsOne);
    expect(
      find.descendant(of: _submitPill, matching: find.text('SAVE CHANGES')),
      findsOne,
    );
    await tester.tap(eye);
    await tester.pumpAndSettle();
    expect(app.current.screen, Screen.bandPreview);
    expect(app.current.param, app.bandId);
    semantics.dispose();
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
    await tester.tap(_submitPill);
    await tester.pumpAndSettle();
    expect(find.text("YOU'RE LIVE"), findsOne);

    await tester.tap(find.text('START ANOTHER'));
    await tester.pumpAndSettle();

    expect(harness.app.nbCreated, isFalse);
    expect(harness.app.canCreateBand, isFalse);
    expect(harness.app.nbGenres, isEmpty);
    expect(find.text('Static Bloom'), findsNothing);
    expect(
      find.bySemanticsLabel('Still needs a name + a genre + a home base'),
      findsOne,
    );
    for (final key in const [
      ValueKey('create-band-name'),
      ValueKey('create-home-base'),
      ValueKey('create-about'),
      ValueKey('create-instagram'),
      ValueKey('create-bandcamp'),
      ValueKey('create-youtube'),
    ]) {
      expect(
        tester.widget<TextField>(find.byKey(key)).controller!.text,
        isEmpty,
      );
    }
    expect(find.byKey(const ValueKey('edit-genres-chip-punk')), findsNothing);
    expect(
      tester
          .widget<EpMonoText>(find.byKey(const ValueKey('edit-genres-count')))
          .text,
      '0 OF 3',
    );
    expect(find.text('0 / 160'), findsOne);
  });

  testWidgets('the create bar goes pending while the save is in flight', (
    tester,
  ) async {
    final repository = _GatedDemoRepository(auth: FakeAuthService());
    final createGate = repository.createGate;
    final app = (await _pumpBandCreate(tester, repository: repository)).app;
    await _fillForm(tester);

    await tester.tap(_submitPill);
    await tester.pump();
    expect(find.text('CREATING…'), findsOne);
    expect(tester.widget<EpPill>(_submitPill).onPressed, isNull);
    expect(repository.createCalls, 1);

    createGate.complete();
    await tester.pumpAndSettle();
    expect(app.nbCreated, isTrue);
    expect(find.text("YOU'RE LIVE"), findsOne);
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

  testWidgets('an unready create is visibly and semantically disabled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = (await _pumpBandCreate(tester)).app;
    expect(tester.widget<EpPill>(_submitPill).onPressed, isNull);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Create band'))
          .flagsCollection
          .isEnabled,
      Tristate.isFalse,
    );
    expect(
      find.bySemanticsLabel('Still needs a name + a genre + a home base'),
      findsOne,
    );
    expect(app.nbCreated, isFalse);
    semantics.dispose();
  });
}

final _submitPill = find.descendant(
  of: find.byKey(const ValueKey('create-band-submit')),
  matching: find.byType(EpPill),
);

/// The bordered surface that holds the three link rows (not an EpCard).
final _linksCard = find
    .ancestor(
      of: find.byKey(const ValueKey('create-instagram')),
      matching: find.byWidgetPredicate((widget) {
        if (widget is! DecoratedBox) return false;
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.border != null &&
            decoration.color != null;
      }),
    )
    .first;

Future<AppHarness> _pumpBandCreate(
  WidgetTester tester, {
  EarplugRepository? repository,
  Widget home = const Scaffold(body: BandCreateScreen()),
}) {
  tester.view.devicePixelRatio = 1;
  return pumpApp(
    tester,
    repository: repository,
    beforePump: (app) async {
      await tester.pumpAndSettle();
      app.startBandCreate();
    },
    home: home,
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
  final input = find.byKey(const ValueKey('edit-genres-input'));
  await tester.scrollUntilVisible(
    input,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.enterText(input, 'punk');
  await tester.pumpAndSettle();
  final punk = find.byKey(const ValueKey('edit-genres-suggestion-0'));
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
  await tester.tap(_submitPill);
  await tester.pumpAndSettle();
}

class _GatedDemoRepository extends StubRepository {
  _GatedDemoRepository({required super.auth});

  late final createGate = gate('createBand');
  int get createCalls => callsTo('createBand');
}
