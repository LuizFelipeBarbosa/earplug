import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  test('Instagram links normalize handles and scheme-less profile URLs', () {
    expect(
      bandLinkUri('@foghorn.diet', instagram: true).toString(),
      'https://instagram.com/foghorn.diet',
    );
    expect(
      bandLinkUri('instagram.com/foghorn.diet', instagram: true).toString(),
      'https://instagram.com/foghorn.diet',
    );
    expect(
      bandLinkUri('www.instagram.com/foghorn.diet', instagram: true).toString(),
      'https://instagram.com/foghorn.diet',
    );
    expect(
      bandLinkUri(
        'http://www.instagram.com/foghorn.diet?hl=en',
        instagram: true,
      ).toString(),
      'https://instagram.com/foghorn.diet?hl=en',
    );
  });

  testWidgets('profile renders the pinned video and clip grid', (tester) async {
    await _pumpProfile(tester);
    final pinned = DemoData.b1Media.singleWhere((media) => media.pinned);
    final clip = DemoData.b1Media.firstWhere(
      (media) => media.isVideo && !media.pinned,
    );

    expect(find.text(pinned.title), findsOne);
    expect(find.text(clip.title), findsOne);
    expect(find.text('CLIPS'), findsOne);
  });

  testWidgets('profile renders all demo photo tiles', (tester) async {
    await _pumpProfile(tester);

    await tester.scrollUntilVisible(
      find.text('PHOTOS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PHOTOS'), findsOne);
    for (final photo in DemoData.b1Media.where(
      (media) => media.kind == MediaKind.photo,
    )) {
      expect(find.byKey(ValueKey('band-photo-${photo.id}')), findsOne);
    }
  });

  testWidgets('a processing clip stays on the profile and shows a toast', (
    tester,
  ) async {
    final harness = await _pumpProfile(tester);
    final clip = DemoData.b1Media.firstWhere(
      (media) => media.isVideo && !media.pinned,
    );
    final clipTitle = find.text(clip.title);
    await tester.ensureVisible(clipTitle);
    await tester.pumpAndSettle();

    await tester.tap(clipTitle);
    await tester.pump();

    expect(harness.app.toast, 'That clip is still processing.');
    expect(find.byType(BandProfileScreen), findsOne);
    expect(
      Navigator.of(tester.element(find.byType(BandProfileScreen))).canPop(),
      isFalse,
    );

    // Flush app.say's 2.2s toast-clear timer so teardown sees no pending timer.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('band avatar falls back to initials without a hero photo', (
    tester,
  ) async {
    final harness = await _pumpProfile(tester);
    final band = harness.app.band('b1')!;

    expect(band.heroUrl, isNull);
    expect(find.text(band.initials), findsOne);
  });

  testWidgets('profile renders every configured band link', (tester) async {
    final harness = await _pumpProfile(tester);
    final band = harness.app.band('b1')!;
    await harness.app.saveBandProfile(
      BandProfileUpdate(
        bandId: band.id,
        name: band.name,
        genres: band.genres,
        area: band.area,
        bio: band.bio,
        linkIg: '@foghorn.diet',
        linkBc: 'foghorn.bandcamp.com',
        linkYt: 'youtube.com/@foghorn',
        credits: band.credits ?? '',
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('YOUTUBE ↗'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('INSTAGRAM ↗'), findsOne);
    expect(find.text('BANDCAMP ↗'), findsOne);
    expect(find.text('YOUTUBE ↗'), findsOne);
  });
}

Future<AppHarness> _pumpProfile(WidgetTester tester) => pumpApp(
  tester,
  home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
);
