import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:earplug/widgets/genre_autocomplete_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
  testWidgets(
    'editor opens on the identity fields with one links card and save action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(
        tester,
        size: const Size(390, 3000),
        home: const Scaffold(body: BandEditScreen()),
      );

      expect(find.text('EDIT BAND'), findsOne);
      expect(find.byKey(const ValueKey('band-identity-header')), findsNothing);
      expect(
        find.byKey(const ValueKey('band-header-image-control')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('band-header-change')), findsNothing);
      expect(find.byKey(const ValueKey('band-artwork-error')), findsNothing);
      expect(
        find.text('Shown at the top of your public page.'),
        findsNothing,
      );
      expect(find.text('Header image'), findsNothing);
      expect(find.bySemanticsLabel('Back'), findsOne);
      expect(find.bySemanticsLabel('Preview public page'), findsOne);
      expect(find.text('BAND NAME · REQUIRED'), findsOne);
      expect(find.bySemanticsLabel('BAND NAME · REQUIRED'), findsOne);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-band-name')))
            .style
            ?.fontSize,
        18,
      );
      expect(find.text('GENRES · REQUIRED'), findsOne);
      expect(find.text('HOME BASE · REQUIRED'), findsOne);
      expect(find.bySemanticsLabel('HOME BASE · REQUIRED'), findsOne);
      expect(find.text('ABOUT'), findsOne);
      expect(find.bySemanticsLabel('ABOUT'), findsOne);
      expect(find.text('LINKS'), findsOne);
      expect(find.text('CREDITS'), findsNothing);
      expect(find.byKey(const ValueKey('edit-credits')), findsNothing);
      expect(find.text('MANAGE VIDEOS AND PHOTOS'), findsNothing);
      expect(find.textContaining('ACCEPTED MEMBERS'), findsNothing);
      expect(find.text('PREVIEW'), findsNothing);
      expect(find.text('PROFILE IMAGE'), findsNothing);
      expect(
        find.byKey(const ValueKey('band-profile-image-control')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('band-profile-avatar-frame')),
        findsNothing,
      );

      final save = find.byKey(const ValueKey('save-band-profile'));
      final pill = tester.widget<EpPill>(save);
      expect(pill.label, 'Save');
      expect(pill.variant, EpPillVariant.primary);
      expect(pill.size, EpPillSize.chip);
      expect(pill.onPressed, isNotNull);
      expect(find.descendant(of: save, matching: find.text('SAVE')), findsOne);
      expect(find.text('SAVE CHANGES'), findsNothing);
      expect(find.byType(StickyActionBar), findsNothing);

      final header = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const ValueKey('band-edit-back')),
              matching: find.byType(Row),
            )
            .first,
      );
      final saveRect = tester.getRect(save);
      expect(saveRect.top, greaterThanOrEqualTo(header.top));
      expect(saveRect.bottom, lessThanOrEqualTo(header.bottom));
      expect(saveRect.right, 390 - 16);
      final eye = tester.getRect(find.byKey(const ValueKey('band-edit-preview')));
      expect(saveRect.left, eye.right + 8);
      final nameLabel = tester.getRect(find.text('BAND NAME · REQUIRED'));
      expect(nameLabel.top, header.bottom + 18);

      expect(find.byType(EpCard), findsNothing);
      final linksCard = find
          .ancestor(
            of: find.byKey(const ValueKey('edit-instagram')),
            matching: find.byWidgetPredicate((widget) {
              if (widget is! DecoratedBox) return false;
              final decoration = widget.decoration;
              return decoration is BoxDecoration &&
                  decoration.border != null &&
                  decoration.color != null;
            }),
          )
          .first;
      expect(linksCard, findsOne);
      expect(
        find.descendant(of: linksCard, matching: find.byType(TextField)),
        findsNWidgets(3),
      );
      for (final (key, hint) in const [
        (ValueKey('edit-instagram'), 'Instagram'),
        (ValueKey('edit-bandcamp'), 'Bandcamp'),
        (ValueKey('edit-youtube'), 'YouTube'),
      ]) {
        final field = find.byKey(key);
        expect(find.ancestor(of: field, matching: linksCard), findsOne);
        final decoration = tester.widget<TextField>(field).decoration!;
        expect(decoration.hintText, hint);
        expect(decoration.labelText, isNull);
        expect(decoration.border, InputBorder.none);
        await tester.enterText(field, '');
        await tester.pumpAndSettle();
        expect(find.text(hint), findsOne);
      }
      semantics.dispose();
    },
  );

  testWidgets('about limits the bio and updates its live counter', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandEditScreen()));
    final bio = find.byKey(const ValueKey('edit-short-bio'));
    await _scrollToFinder(tester, bio);
    expect(tester.widget<TextField>(bio).maxLength, 160);
    await tester.enterText(bio, 'A fresh band bio!!');
    await tester.pump();
    final counter = find.byKey(const ValueKey('edit-short-bio-count'));
    expect(
      find.descendant(of: counter, matching: find.text('18 / 160')),
      findsOne,
    );
    await tester.enterText(bio, 'Short');
    await tester.pump();
    expect(
      find.descendant(of: counter, matching: find.text('5 / 160')),
      findsOne,
    );
  });

  testWidgets(
    'genres use autocomplete, custom entries, and a three-genre limit',
    (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 1800),
        home: const Scaffold(body: BandEditScreen()),
      );
      final originalGenres = tester
          .widget<GenreAutocompleteField>(find.byType(GenreAutocompleteField))
          .selected;
      final input = find.byKey(const ValueKey('edit-genres-input'));
      await tester.enterText(input, 'doom jazz');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-genres-suggestions')), findsOne);
      await tester.tap(find.byKey(const ValueKey('edit-genres-add-custom')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('edit-genres-chip-doom jazz')),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('edit-genres-suggestions')),
        findsNothing,
      );
      expect(
        tester
            .widget<EpMonoText>(find.byKey(const ValueKey('edit-genres-count')))
            .text,
        '${originalGenres.length + 1} OF 3',
      );
      expect(tester.widget<TextField>(input).enabled, isFalse);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('edit-genres-chip-doom jazz')),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).enabled, isTrue);
      await tester.enterText(input, 'surf');
      await tester.pumpAndSettle();
      final suggestion = find.byKey(const ValueKey('edit-genres-suggestion-0'));
      expect(suggestion, findsOne);
      await tester.tap(suggestion);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('edit-genres-chip-surf')), findsOne);
    },
  );

  testWidgets('header preview opens the public preview', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandEditScreen()),
    );
    harness.app.openBandEditor();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('band-edit-preview')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bandPreview);
    expect(harness.app.current.param, harness.app.bandId);
  });

  testWidgets('header back pops to the previous navigation entry', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandEditScreen()),
    );
    harness.app.go(Screen.band, 'b1');
    harness.app.openBandEditor();
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.bandEdit);
    await tester.tap(find.byKey(const ValueKey('band-edit-back')));
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.band);
    expect(harness.app.current.param, 'b1');
  });

  testWidgets('links deep-link scrolls to the links card', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandEditScreen()),
    );
    harness.app.openBandEditor(section: 'links');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('edit-instagram')).hitTestable(),
      findsOne,
    );
    expect(find.byKey(const ValueKey('edit-youtube')).hitTestable(), findsOne);
  });

  testWidgets('archive dialog preserves irreversible consequence copy', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandEditScreen()));
    await _scrollToKey(tester, const Key('archive-band'));
    await tester.tap(find.byKey(const Key('archive-band')));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot restore'), findsOne);
    expect(
      find.textContaining('Historical and shared records are preserved'),
      findsOne,
    );
    expect(find.text('KEEP BAND'), findsOne);
    await tester.tap(find.text('KEEP BAND'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'editor scrolls without overflow at 390x844 and ${scale}x text',
      (tester) async {
        await pumpApp(
          tester,
          size: const Size(390, 844),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(body: BandEditScreen()),
          ),
        );
        expect(tester.takeException(), isNull);
        for (var page = 0; page < 8; page++) {
          // Drag the gutter so a multiline field cannot consume the gesture.
          await tester.dragFrom(const Offset(8, 600), const Offset(0, -500));
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await _scrollToKey(tester, const Key('archive-band'));
        expect(find.byKey(const Key('archive-band')).hitTestable(), findsOne);
        expect(tester.takeException(), isNull);
        expect(find.byType(StickyActionBar), findsNothing);
        await _scrollToTop(tester);
        expect(
          find.byKey(const ValueKey('save-band-profile')).hitTestable(),
          findsOne,
        );
      },
    );
  }

  testWidgets('profile changes remain local until one explicit atomic save', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandEditScreen()),
    );
    final originalColor = harness.app.myBand!.color;
    final originalCredits = harness.app.myBand!.credits ?? '';

    await tester.enterText(
      find.byKey(const ValueKey('edit-band-name')),
      'New Rhythm',
    );
    expect(harness.app.myBand!.name, 'Foghorn Diet');

    await _scrollToKey(tester, const ValueKey('edit-short-bio'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-short-bio')),
      'A concise new bio.',
    );
    await _scrollToKey(tester, const ValueKey('edit-instagram'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-instagram')),
      '@newrhythm',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-bandcamp')),
      'newrhythm.bandcamp.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('edit-youtube')),
      'youtube.com/@newrhythm',
    );
    expect(find.byKey(const ValueKey('edit-credits')), findsNothing);
    expect(harness.app.myBand!.bio, isNot('A concise new bio.'));

    await _tapSave(tester);
    await tester.pumpAndSettle();

    final updated = harness.app.myBand!;
    expect(updated.name, 'New Rhythm');
    expect(updated.initials, 'NR');
    expect(updated.color, originalColor);
    expect(updated.bio, 'A concise new bio.');
    expect(updated.linkIg, '@newrhythm');
    expect(updated.linkBc, 'newrhythm.bandcamp.com');
    expect(updated.linkYt, 'youtube.com/@newrhythm');
    expect(updated.credits, originalCredits);
    expect(find.text('Changes saved.'), findsOne);
  });

  testWidgets('profile saves never create, rotate, or revoke invitations', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _InviteAuditRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandEditScreen()),
    );

    await _tapSave(tester);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-band-name')),
      'Profile Only Change',
    );
    await _tapSave(tester);
    await tester.pumpAndSettle();

    expect(repository.profileUpdates, 2);
    expect(repository.inviteCreates, 0);
    expect(repository.inviteRotations, 0);
    expect(repository.inviteRevocations, 0);
  });

  testWidgets('late private details hydrate without overwriting other edits', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final details = Completer<BandProfileDetails>();
    final repository = StubRepository(auth: auth)
      ..returns('bandProfileDetails', details.future);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandEditScreen()),
    );

    await tester.enterText(
      find.byKey(const ValueKey('edit-band-name')),
      'Keep This Draft',
    );
    details.complete(
      const BandProfileDetails(
        credits: 'Existing private credits',
        linkIg: '@existing',
        memberNames: ['Band admin'],
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToKey(tester, const ValueKey('edit-instagram'));
    final instagram = tester.widget<TextField>(
      find.byKey(const ValueKey('edit-instagram')),
    );
    expect(instagram.controller!.text, '@existing');
    expect(find.byKey(const ValueKey('edit-credits')), findsNothing);

    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(harness.app.myBand!.name, 'Keep This Draft');
    expect(harness.app.myBand!.credits, 'Existing private credits');
  });

  testWidgets(
    'required validation is inline and leaves the draft recoverable',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: BandEditScreen()),
      );
      await tester.enterText(
        find.byKey(const ValueKey('edit-band-name')),
        '   ',
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('Band name, sound, and home base are required.'),
        findsOne,
      );
      expect(harness.app.myBand!.name, 'Foghorn Diet');

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edit-band-name')),
        'Recovered Name',
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();
      expect(harness.app.myBand!.name, 'Recovered Name');
      expect(find.text('Changes saved.'), findsOne);
    },
  );

  testWidgets('save exposes pending, failure, and retry success states', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ControlledProfileRepository(auth: auth);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandEditScreen()),
    );

    final save = find.byKey(const ValueKey('save-band-profile'));
    await _tapSave(tester);
    await tester.pump();
    expect(find.descendant(of: save, matching: find.text('SAVING…')), findsOne);
    expect(tester.widget<EpPill>(save).onPressed, isNull);

    repository.firstSave.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOne);
    await _scrollToTop(tester);
    expect(find.descendant(of: save, matching: find.text('SAVE')), findsOne);
    expect(tester.widget<EpPill>(save).onPressed, isNotNull);

    await _tapSave(tester);
    await tester.pumpAndSettle();
    expect(repository.updateCalls, 2);
    expect(find.text('Changes saved.'), findsOne);
  });

  testWidgets(
    'archive requires the exact band name and returns to fan profile',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: BandEditScreen()),
      );
      await _scrollToKey(tester, const Key('archive-band'));
      await tester.tap(find.byKey(const Key('archive-band')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const Key('archive-band-confirmation'));
      await tester.enterText(confirm, 'Wrong name');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ARCHIVE BAND'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(confirm, 'Foghorn Diet');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'ARCHIVE BAND'));
      await tester.pumpAndSettle();

      expect(harness.app.current.screen, Screen.myGigs);
      expect(harness.app.myBands, isNot(contains('b1')));
    },
  );

  testWidgets('archive timeout succeeds when status proves it committed', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..wraps<BandArchiveResult>(
          'archiveBand',
          (_) => throw TimeoutException('response lost after commit'),
        ),
      home: const Scaffold(body: BandEditScreen()),
    );

    await expectLater(harness.app.archiveCurrentBand(), completes);
    expect(harness.app.myBands, isNot(contains('b1')));
    expect(harness.app.current.screen, Screen.myGigs);
  });

  testWidgets('unverified archive keeps the band available for retry', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..fail('archiveBand', StateError('archive did not commit'))
        ..returns(
          'bandArchiveStatus',
          const BandArchiveStatus(bandId: 'b1', archivedAt: null),
        ),
      home: const Scaffold(body: BandEditScreen()),
    );

    await expectLater(harness.app.archiveCurrentBand(), throwsStateError);
    expect(harness.app.myBands, contains('b1'));
    expect(harness.app.bandId, 'b1');
  });
}

/// Brings the header back into view and taps its Save pill. Callers pump
/// afterwards so pending and settled states can both be observed.
Future<void> _tapSave(WidgetTester tester) async {
  await _scrollToTop(tester);
  final save = find.byKey(const ValueKey('save-band-profile'));
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
}

/// Drops field focus first: a focused field re-reveals its caret after any
/// jump and would drag the header back out of the viewport.
Future<void> _scrollToTop(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
  await _scrollToFinder(tester, find.byKey(key));
}

Future<void> _scrollToFinder(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 20 && target.evaluate().isEmpty; attempt++) {
    final list = find.byType(ListView);
    final start =
        tester.getTopLeft(list) + Offset(8, tester.getSize(list).height * .75);
    await tester.dragFrom(start, const Offset(0, -500));
    await tester.pump();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

class _ControlledProfileRepository extends DemoRepository {
  _ControlledProfileRepository({required super.auth});

  final firstSave = Completer<void>();
  int updateCalls = 0;

  @override
  Future<void> updateBandProfile(BandProfileUpdate update) async {
    updateCalls++;
    if (updateCalls == 1) await firstSave.future;
    await super.updateBandProfile(update);
  }
}

class _InviteAuditRepository extends StubRepository {
  _InviteAuditRepository({required super.auth});

  int get profileUpdates => callsTo('updateBandProfile');
  int get inviteCreates => callsTo('createBandInvite');
  int get inviteRotations => callsTo('rotateBandInvite');
  int get inviteRevocations => callsTo('revokeBandInvite');
}
