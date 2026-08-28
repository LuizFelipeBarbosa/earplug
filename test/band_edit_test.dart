import 'dart:async';

import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_edit.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('editor groups every profile field and uses plain terminology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, home: const Scaffold(body: BandEditScreen()));

    expect(find.text('EDIT PROFILE'), findsOne);
    expect(find.text('Required details'), findsOne);
    // The remaining match is the field hint, not a duplicate heading.
    expect(find.text('Band name'), findsOne);
    expect(find.bySemanticsLabel('Band name'), findsOne);
    expect(find.text('Sound / genres'), findsOne);
    expect(find.text('Home base'), findsNothing);
    expect(find.bySemanticsLabel('Home base'), findsOne);
    expect(find.text('PREVIEW PUBLIC PROFILE'), findsOne);
    await _scrollTo(tester, 'Optional details');
    expect(find.text('Short bio'), findsNothing);
    expect(find.bySemanticsLabel('Short bio'), findsOne);
    expect(find.text('Links'), findsOne);
    expect(find.text('Credits'), findsNothing);
    expect(find.bySemanticsLabel('Credits'), findsOne);
    expect(find.text('Music and clips'), findsNothing);
    await _scrollTo(tester, 'Band members');
    expect(find.text('Band members'), findsOne);
    expect(find.text('Accepted members'), findsOne);
    expect(find.text('Invitation link'), findsNothing);
    expect(find.text('Sleeve notes'), findsNothing);
    expect(find.text('Home taping'), findsNothing);
    expect(find.text('PREVIEW AS FAN'), findsNothing);
    semantics.dispose();
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
      await tester.pump();

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

    expect(find.text('Band members'), findsOne);
    expect(find.text('Band admin'), findsOne);
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
}

Future<void> _scrollTo(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToKey(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    260,
    scrollable: find.byType(Scrollable).first,
  );
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
