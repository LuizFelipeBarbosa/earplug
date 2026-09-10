import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_identity_editor.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/stub_repository.dart';
import 'support/ui_test_helpers.dart';

void main() {
  testWidgets('editor groups every profile field and uses plain terminology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, home: const Scaffold(body: BandEditScreen()));
    tester.view.physicalSize = const Size(402, 5000);
    await tester.pumpAndSettle();

    expect(findUiText('EDIT BAND'), findsOne);
    expect(find.byType(BandIdentityHeader), findsNothing);
    await openAllFormSections(tester);
    expect(find.byType(BandIdentityHeader), findsOne);
    expect(find.byKey(const ValueKey('band-profile-image-control')), findsOne);
    expect(find.byKey(const ValueKey('band-header-image-control')), findsOne);
    expect(findUiText('BAND NAME · REQUIRED'), findsOne);
    expect(findUiSemantics('BAND NAME · REQUIRED'), findsOne);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('edit-band-name')))
          .style
          ?.fontSize,
      16,
    );
    expect(findUiText('GENRES · REQUIRED'), findsOne);
    expect(findUiText('HOME BASE · REQUIRED'), findsOne);
    expect(findUiSemantics('HOME BASE · REQUIRED'), findsOne);
    expect(findUiText('ABOUT'), findsOne);
    expect(findUiSemantics('ABOUT'), findsOne);
    expect(findUiText('PREVIEW'), findsOne);
    expect(find.byType(StickyActionBar), findsOne);
    expect(findUiText('Links and credits'), findsOne);
    expect(findUiText('CREDITS'), findsWidgets);
    expect(
      find.bySemanticsLabel(RegExp('^Credits', caseSensitive: false)),
      findsOne,
    );
    expect(findUiText('MANAGE VIDEOS AND PHOTOS'), findsOne);
    await openAllFormSections(tester);
    expect(findUiText('Members'), findsOne);
    expect(findUiText('ACCEPTED MEMBERS'), findsOne);
    expect(find.text('Invitation link'), findsNothing);
    expect(find.text('Sleeve notes'), findsNothing);
    expect(find.text('Home taping'), findsNothing);
    expect(findUiText('PREVIEW AS FAN'), findsNothing);

    for (final key in const [
      ValueKey('edit-instagram'),
      ValueKey('edit-bandcamp'),
      ValueKey('edit-youtube'),
    ]) {
      expect(
        find.ancestor(of: find.byKey(key), matching: find.byType(EpCard)),
        findsNothing,
      );
    }
    semantics.dispose();
  });

  testWidgets('custom genres use a ghost add flow without a band bio limit', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandEditScreen()));
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    final addChip = tester.widget<TextButton>(
      find.byKey(const ValueKey('show-custom-genre')),
    );
    expect(addChip.onPressed, isNotNull);
    expect(find.byKey(const ValueKey('edit-custom-genre')), findsNothing);

    await revealFormKey(tester, const ValueKey('show-custom-genre'));

    await tester.tap(find.byKey(const ValueKey('show-custom-genre')));
    await tester.pumpAndSettle();
    await revealFormKey(tester, const ValueKey('edit-custom-genre'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-custom-genre')),
      'doom jazz',
    );
    await tester.tap(findUiControl(FilledButton, 'ADD'));
    await tester.pumpAndSettle();

    expect(find.textContaining('doom jazz'), findsOne);
    expect(find.byKey(const ValueKey('edit-custom-genre')), findsNothing);
    await _scrollToKey(tester, const ValueKey('edit-short-bio'));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('edit-short-bio')))
          .maxLength,
      isNull,
    );
  });

  testWidgets(
    'profile and header images edit independently without losing the draft',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: BandEditScreen()),
      );
      await revealFormKey(tester, const ValueKey('edit-band-name'));
      await tester.enterText(
        find.byKey(const ValueKey('edit-band-name')),
        'Unsaved New Name',
      );

      harness.picker.nextPhoto = photoFixture(filename: 'new_banner.png');
      await revealFormKey(tester, const ValueKey('band-header-image-control'));
      await tester.tap(find.byKey(const ValueKey('band-header-image-control')));
      await tester.pumpAndSettle();
      expect(findUiText('REPLACE'), findsOne);
      expect(findUiText('USE INITIALS INSTEAD'), findsNothing);
      await tester.tap(findUiText('REPLACE'));
      await tester.pumpAndSettle();
      harness.picker.nextPhoto = photoFixture(filename: 'new_avatar.png');
      await revealFormKey(tester, const ValueKey('band-profile-image-control'));
      await tester.tap(
        find.byKey(const ValueKey('band-profile-image-control')),
      );
      await tester.pumpAndSettle();
      expect(findUiText('REPLACE'), findsOne);
      expect(findUiText('USE INITIALS INSTEAD'), findsNothing);
      await tester.tap(findUiText('REPLACE'));
      await tester.pumpAndSettle();

      final photos = harness.media.photosFor('b1');
      expect(photos.singleWhere((photo) => photo.isBanner).title, 'NEW BANNER');
      expect(photos.singleWhere((photo) => photo.isAvatar).title, 'NEW AVATAR');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('edit-band-name')))
            .controller!
            .text,
        'Unsaved New Name',
      );
      expect(harness.app.myBand!.name, 'Foghorn Diet');
    },
  );

  testWidgets('artwork sheet removes an assigned profile image', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _ArtworkAuditRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandEditScreen()),
    );

    harness.picker.nextPhoto = photoFixture(filename: 'new_avatar.png');
    final avatar = find.byKey(const ValueKey('band-profile-image-control'));
    await revealFormKey(tester, const ValueKey('band-profile-image-control'));
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(findUiText('REPLACE'), findsOne);
    expect(findUiText('USE INITIALS INSTEAD'), findsNothing);

    await tester.tap(findUiText('REPLACE'));
    await tester.pumpAndSettle();
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(findUiText('REPLACE'), findsOne);
    expect(findUiText('USE INITIALS INSTEAD'), findsOne);

    await tester.tap(findUiText('USE INITIALS INSTEAD'));
    await tester.pumpAndSettle();
    expect(repository.clearAvatarCalls, 1);
    expect(harness.app.myBand!.profileImageUrl, isNull);
    expect(findUiText('FD'), findsOne);
  });

  testWidgets('failed avatar replacement restores the saved artwork', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = StubRepository(auth: auth)
      ..fail('setBandAvatar', StateError('avatar assignment failed'));
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandEditScreen()),
    );

    harness.picker.nextPhoto = photoFixture(filename: 'failed_avatar.png');
    final avatar = find.byKey(const ValueKey('band-profile-image-control'));
    await revealFormKey(tester, const ValueKey('band-profile-image-control'));
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    await tester.tap(findUiText('REPLACE'));
    await tester.pumpAndSettle();

    final avatarFrame = find.byKey(const ValueKey('band-profile-avatar-frame'));

    await revealFormKey(tester, const ValueKey('band-profile-avatar-frame'));
    expect(
      find.descendant(of: avatarFrame, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(of: avatarFrame, matching: findUiText('FD')),
      findsOne,
    );
    expect(find.textContaining('profile image could not be saved'), findsOne);
  });

  testWidgets(
    'accepted members are read-only and archive copy is irreversible',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: BandEditScreen()),
      );
      harness.app.openBandEditor(section: 'members');
      await tester.pumpAndSettle();

      final member = tester.widget<EpChip>(
        find.byKey(const ValueKey('accepted-member-Band admin')),
      );
      expect(member.onTap, isNull);
      expect(member.onRemoved, isNull);

      await _scrollTo(tester, 'ARCHIVE BAND');
      expect(find.byType(DangerZone), findsOne);
      expect(find.textContaining('cannot restore'), findsOne);
      expect(
        find.textContaining('Historical and shared records remain'),
        findsOne,
      );
    },
  );

  testWidgets('editor remains usable at two-times text scale', (tester) async {
    await pumpApp(
      tester,
      home: const MediaQuery(
        data: MediaQueryData(
          size: Size(402, 900),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(body: BandEditScreen()),
      ),
    );

    for (var page = 0; page < 8; page++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(find.byType(StickyActionBar), findsOne);
  });

  testWidgets('profile changes remain local until one explicit atomic save', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandEditScreen()),
    );
    final originalColor = harness.app.myBand!.color;

    await revealFormKey(tester, const ValueKey('edit-band-name'));

    await tester.enterText(
      find.byKey(const ValueKey('edit-band-name')),
      'New Rhythm',
    );
    expect(harness.app.myBand!.name, 'Foghorn Diet');

    await _scrollToKey(tester, const ValueKey('edit-short-bio'));
    await revealFormKey(tester, const ValueKey('edit-short-bio'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-short-bio')),
      'A concise new bio.',
    );
    await _scrollToKey(tester, const ValueKey('edit-instagram'));
    await revealFormKey(tester, const ValueKey('edit-instagram'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-instagram')),
      '@newrhythm',
    );
    await revealFormKey(tester, const ValueKey('edit-bandcamp'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-bandcamp')),
      'newrhythm.bandcamp.com',
    );
    await revealFormKey(tester, const ValueKey('edit-youtube'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-youtube')),
      'youtube.com/@newrhythm',
    );
    await _scrollToKey(tester, const ValueKey('edit-credits'));
    await revealFormKey(tester, const ValueKey('edit-credits'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-credits')),
      'Recorded by Mara K.',
    );
    expect(harness.app.myBand!.bio, isNot('A concise new bio.'));

    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(findUiText('SAVE CHANGES'));
    await tester.pumpAndSettle();

    final updated = harness.app.myBand!;
    expect(updated.name, 'New Rhythm');
    expect(updated.initials, 'NR');
    expect(updated.color, originalColor);
    expect(updated.bio, 'A concise new bio.');
    expect(updated.linkIg, '@newrhythm');
    expect(updated.linkBc, 'newrhythm.bandcamp.com');
    expect(updated.linkYt, 'youtube.com/@newrhythm');
    expect(updated.credits, 'Recorded by Mara K.');
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

    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(findUiText('SAVE CHANGES'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
    await tester.pumpAndSettle();
    await revealFormKey(tester, const ValueKey('edit-band-name'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-band-name')),
      'Profile Only Change',
    );
    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(findUiText('SAVE CHANGES'));
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

    await revealFormKey(tester, const ValueKey('edit-band-name'));

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
    await _scrollToKey(tester, const ValueKey('edit-credits'));
    final credits = tester.widget<TextField>(
      find.byKey(const ValueKey('edit-credits')),
    );
    expect(credits.controller!.text, 'Existing private credits');

    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(findUiText('SAVE CHANGES'));
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
      await revealFormKey(tester, const ValueKey('edit-band-name'));
      await tester.enterText(
        find.byKey(const ValueKey('edit-band-name')),
        '   ',
      );
      await _scrollTo(tester, 'SAVE CHANGES');
      await tester.tap(findUiText('SAVE CHANGES'));
      await tester.pumpAndSettle();

      expect(find.text('Enter band name.'), findsOne);
      expect(harness.app.myBand!.name, 'Foghorn Diet');

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
      await tester.pumpAndSettle();
      await revealFormKey(tester, const ValueKey('edit-band-name'));
      await tester.enterText(
        find.byKey(const ValueKey('edit-band-name')),
        'Recovered Name',
      );
      await _scrollTo(tester, 'SAVE CHANGES');
      await tester.tap(findUiText('SAVE CHANGES'));
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

    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(findUiText('SAVE CHANGES'));
    await tester.pump();
    expect(findUiText('SAVING…'), findsOne);

    repository.firstSave.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOne);
    expect(findUiText('SAVE CHANGES'), findsOne);

    await tester.tap(findUiText('SAVE CHANGES'));
    await tester.pumpAndSettle();
    expect(repository.updateCalls, 2);
    expect(find.text('Changes saved.'), findsOne);
  });

  testWidgets('member panel creates, rotates, and revokes secure links', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: BandEditScreen()),
    );
    harness.app.openBandEditor(section: 'members');
    await tester.pumpAndSettle();

    await openAllFormSections(tester);
    expect(findUiText('Members'), findsOne);
    expect(findUiText('BAND ADMIN'), findsOne);
    await _scrollTo(tester, 'CREATE INVITATION LINK');
    await tester.tap(findUiText('CREATE INVITATION LINK'));
    await tester.pumpAndSettle();
    final first = harness.app.inviteFor(harness.app.bandId)!;
    expect(find.text(first.url), findsOne);
    expect(findUiText('COPY INVITATION LINK'), findsOne);

    await tester.tap(findUiText('ROTATE LINK'));
    await tester.pumpAndSettle();
    final rotated = harness.app.inviteFor(harness.app.bandId)!;
    expect(rotated.token, isNot(first.token));

    await tester.tap(findUiText('REVOKE LINK'));
    await tester.pumpAndSettle();
    expect(find.text('The previous invitation was revoked.'), findsOne);
    expect(findUiText('CREATE NEW INVITATION LINK'), findsOne);
  });

  testWidgets('member panel trusts server invitation expiry state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _InviteStateRepository(
      auth: auth,
      invite: BandInvite(
        bandId: 'b1',
        token: 'server-active',
        expiresAt: DateTime.utc(2000),
        revoked: false,
        expired: false,
      ),
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandEditScreen()),
    );
    harness.app.openBandEditor(section: 'members');
    await tester.pumpAndSettle();

    expect(find.text(repository.invite.url), findsOne);
    expect(findUiText('COPY INVITATION LINK'), findsOne);

    repository.invite = BandInvite(
      bandId: 'b1',
      token: 'server-expired',
      expiresAt: DateTime.utc(2100),
      revoked: false,
      expired: true,
    );
    await harness.app.refreshBandInvite('b1');
    await tester.pumpAndSettle();

    expect(find.text('The previous invitation expired.'), findsOne);
    expect(findUiText('CREATE NEW INVITATION LINK'), findsOne);
  });

  testWidgets(
    'archive requires the exact band name and returns to fan profile',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: BandEditScreen()),
      );
      await _scrollTo(tester, 'ARCHIVE BAND');
      await tester.tap(findUiText('ARCHIVE BAND'));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const Key('archive-band-confirmation'));

      await revealFormKey(tester, const Key('archive-band-confirmation'));
      await tester.enterText(confirm, 'Wrong name');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(findUiControl(FilledButton, 'ARCHIVE BAND'))
            .onPressed,
        isNull,
      );
      await tester.enterText(confirm, 'Foghorn Diet');
      await tester.pump();
      await tester.tap(findUiControl(FilledButton, 'ARCHIVE BAND'));
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

Future<void> _scrollTo(WidgetTester tester, String text) async {
  await _scrollToFinder(tester, findUiText(text));
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
  await revealFormKey(tester, key);
  await _scrollToFinder(tester, find.byKey(key));
}

Future<void> _scrollToFinder(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 20 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView), const Offset(0, -500));
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

class _ArtworkAuditRepository extends StubRepository {
  _ArtworkAuditRepository({required super.auth});

  int get clearAvatarCalls => callsTo('clearBandAvatar');
}

class _InviteStateRepository extends DemoRepository {
  _InviteStateRepository({required super.auth, required this.invite});

  BandInvite invite;

  @override
  Future<BandInvite?> bandInvite(String bandId) async => invite;
}

class _InviteAuditRepository extends StubRepository {
  _InviteAuditRepository({required super.auth});

  int get profileUpdates => callsTo('updateBandProfile');
  int get inviteCreates => callsTo('createBandInvite');
  int get inviteRotations => callsTo('rotateBandInvite');
  int get inviteRevocations => callsTo('revokeBandInvite');
}
