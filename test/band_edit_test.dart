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

void main() {
  testWidgets('editor groups every profile field and uses plain terminology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, home: const Scaffold(body: BandEditScreen()));
    tester.view.physicalSize = const Size(402, 5000);
    await tester.pumpAndSettle();

    expect(find.text('EDIT BAND'), findsOne);
    expect(find.byType(BandIdentityHeader), findsOne);
    expect(find.byKey(const ValueKey('band-profile-image-control')), findsOne);
    expect(find.byKey(const ValueKey('band-header-image-control')), findsOne);
    expect(find.text('BAND NAME · REQUIRED'), findsOne);
    expect(find.bySemanticsLabel('BAND NAME · REQUIRED'), findsOne);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('edit-band-name')))
          .style
          ?.fontSize,
      21,
    );
    expect(find.text('GENRES · REQUIRED'), findsOne);
    expect(find.text('HOME BASE · REQUIRED'), findsOne);
    expect(find.bySemanticsLabel('HOME BASE · REQUIRED'), findsOne);
    expect(find.text('ABOUT'), findsOne);
    expect(find.bySemanticsLabel('ABOUT'), findsOne);
    expect(find.text('PREVIEW'), findsOne);
    expect(find.byType(StickyActionBar), findsOne);
    expect(find.text('LINKS'), findsOne);
    expect(find.text('CREDITS'), findsWidgets);
    expect(find.bySemanticsLabel('Credits'), findsOne);
    expect(find.text('MANAGE VIDEOS AND PHOTOS'), findsOne);
    expect(find.textContaining('BAND MEMBERS'), findsOne);
    expect(find.text('ACCEPTED MEMBERS'), findsOne);
    expect(find.text('Invitation link'), findsNothing);
    expect(find.text('Sleeve notes'), findsNothing);
    expect(find.text('Home taping'), findsNothing);
    expect(find.text('PREVIEW AS FAN'), findsNothing);
    semantics.dispose();
  });

  testWidgets('custom genres use a ghost add flow without a band bio limit', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: BandEditScreen()));
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    final addChip = tester.widget<EpChip>(
      find.byKey(const ValueKey('show-custom-genre')),
    );
    expect(addChip.ghost, isTrue);
    expect(find.byKey(const ValueKey('edit-custom-genre')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('show-custom-genre')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-custom-genre')),
      'doom jazz',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'ADD'));
    await tester.pumpAndSettle();

    expect(find.text('DOOM JAZZ'), findsOne);
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
      await tester.enterText(
        find.byKey(const ValueKey('edit-band-name')),
        'Unsaved New Name',
      );

      harness.picker.nextPhoto = photoFixture(filename: 'new_banner.png');
      await tester.tap(find.byKey(const ValueKey('band-header-image-control')));
      await tester.pumpAndSettle();
      harness.picker.nextPhoto = photoFixture(filename: 'new_avatar.png');
      await tester.tap(
        find.byKey(const ValueKey('band-profile-image-control')),
      );
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
    await _scrollToKey(tester, const ValueKey('edit-credits'));
    await tester.enterText(
      find.byKey(const ValueKey('edit-credits')),
      'Recorded by Mara K.',
    );
    expect(harness.app.myBand!.bio, isNot('A concise new bio.'));

    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(find.text('SAVE CHANGES'));
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
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('edit-band-name')),
      'Profile Only Change',
    );
    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(find.text('SAVE CHANGES'));
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
    final repository = _DelayedDetailsRepository(auth: auth);
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
    repository.details.complete(
      const BandProfileDetails(
        credits: 'Existing private credits',
        linkIg: '@existing',
        memberNames: ['Band admin'],
      ),
    );
    await tester.pumpAndSettle();

    await _scrollToKey(tester, const ValueKey('edit-credits'));
    final credits = tester.widget<TextField>(
      find.byKey(const ValueKey('edit-credits')),
    );
    expect(credits.controller!.text, 'Existing private credits');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('edit-instagram')))
          .controller!
          .text,
      '@existing',
    );

    await _scrollTo(tester, 'SAVE CHANGES');
    await tester.tap(find.text('SAVE CHANGES'));
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
      await _scrollTo(tester, 'SAVE CHANGES');
      await tester.tap(find.text('SAVE CHANGES'));
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
      await _scrollTo(tester, 'SAVE CHANGES');
      await tester.tap(find.text('SAVE CHANGES'));
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
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();
    expect(find.text('SAVING…'), findsOne);

    repository.firstSave.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOne);
    expect(find.text('SAVE CHANGES'), findsOne);

    await tester.tap(find.text('SAVE CHANGES'));
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

    expect(find.textContaining('BAND MEMBERS'), findsOne);
    expect(find.text('BAND ADMIN'), findsOne);
    await tester.tap(find.text('CREATE INVITATION LINK'));
    await tester.pumpAndSettle();
    final first = harness.app.inviteFor(harness.app.bandId)!;
    expect(find.text(first.url), findsOne);
    expect(find.text('COPY INVITATION LINK'), findsOne);

    await tester.tap(find.text('ROTATE LINK'));
    await tester.pumpAndSettle();
    final rotated = harness.app.inviteFor(harness.app.bandId)!;
    expect(rotated.token, isNot(first.token));

    await tester.tap(find.text('REVOKE LINK'));
    await tester.pumpAndSettle();
    expect(find.text('The previous invitation was revoked.'), findsOne);
    expect(find.text('CREATE NEW INVITATION LINK'), findsOne);
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
    expect(find.text('COPY INVITATION LINK'), findsOne);

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
    expect(find.text('CREATE NEW INVITATION LINK'), findsOne);
  });

  testWidgets(
    'archive requires the exact band name and returns to fan profile',
    (tester) async {
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: BandEditScreen()),
      );
      await _scrollTo(tester, 'ARCHIVE BAND');
      await tester.tap(find.text('ARCHIVE BAND'));
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
      repository: _CommittedTimeoutArchiveRepository(auth: auth),
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
      repository: _UnverifiedArchiveRepository(auth: auth),
      home: const Scaffold(body: BandEditScreen()),
    );

    await expectLater(harness.app.archiveCurrentBand(), throwsStateError);
    expect(harness.app.myBands, contains('b1'));
    expect(harness.app.bandId, 'b1');
  });
}

Future<void> _scrollTo(WidgetTester tester, String text) async {
  await _scrollToFinder(tester, find.text(text));
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
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

class _DelayedDetailsRepository extends DemoRepository {
  _DelayedDetailsRepository({required super.auth});

  final details = Completer<BandProfileDetails>();

  @override
  Future<BandProfileDetails> bandProfileDetails(String bandId) =>
      details.future;
}

class _InviteStateRepository extends DemoRepository {
  _InviteStateRepository({required super.auth, required this.invite});

  BandInvite invite;

  @override
  Future<BandInvite?> bandInvite(String bandId) async => invite;
}

class _InviteAuditRepository extends DemoRepository {
  _InviteAuditRepository({required super.auth});

  int profileUpdates = 0;
  int inviteCreates = 0;
  int inviteRotations = 0;
  int inviteRevocations = 0;

  @override
  Future<void> updateBandProfile(BandProfileUpdate update) async {
    profileUpdates++;
    await super.updateBandProfile(update);
  }

  @override
  Future<BandInvite> createBandInvite(String bandId) {
    inviteCreates++;
    return super.createBandInvite(bandId);
  }

  @override
  Future<BandInvite> rotateBandInvite(String bandId) {
    inviteRotations++;
    return super.rotateBandInvite(bandId);
  }

  @override
  Future<void> revokeBandInvite(String bandId) {
    inviteRevocations++;
    return super.revokeBandInvite(bandId);
  }
}

class _CommittedTimeoutArchiveRepository extends DemoRepository {
  _CommittedTimeoutArchiveRepository({required super.auth});

  @override
  Future<BandArchiveResult> archiveBand(String bandId) async {
    await super.archiveBand(bandId);
    throw TimeoutException('response lost after commit');
  }
}

class _UnverifiedArchiveRepository extends DemoRepository {
  _UnverifiedArchiveRepository({required super.auth});

  @override
  Future<BandArchiveResult> archiveBand(String bandId) async =>
      throw StateError('archive did not commit');

  @override
  Future<BandArchiveStatus> bandArchiveStatus(String bandId) async =>
      BandArchiveStatus(bandId: bandId, archivedAt: null);
}
