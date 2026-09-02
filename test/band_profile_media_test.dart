import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_profile.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/band_identity_editor.dart';
import 'package:earplug/widgets/brand_icons.dart';
import 'package:earplug/widgets/video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  test('resolved artwork roles do not resurrect cleared legacy artwork', () {
    final legacyPayload = <String, dynamic>{
      '_id': 'band-1',
      'slug': 'band-1',
      'name': 'Band One',
      'genres': <String>['punk'],
      'area': 'Oakland',
      'colorHex': '#1435F0',
      'initials': 'BO',
      'followerCount': 1,
      'bio': '',
      'heroUrl': 'https://example.com/legacy.jpg',
      'profileComplete': true,
      'discoveryProfileReady': false,
      'pastShows': <dynamic>[],
    };

    final legacy = Band.fromJson(legacyPayload);
    expect(legacy.profileImageUrl, legacy.heroUrl);
    expect(legacy.headerImageUrl, legacy.heroUrl);

    final roleAware = Band.fromJson({
      ...legacyPayload,
      'avatarUrl': null,
      'bannerUrl': 'https://example.com/banner.jpg',
    });
    expect(roleAware.profileImageUrl, isNull);
    expect(roleAware.headerImageUrl, 'https://example.com/banner.jpg');
  });

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

  testWidgets('profile renders every video in one thumbnail section', (
    tester,
  ) async {
    await _pumpProfile(tester);
    final videos = DemoData.b1Media.where((media) => media.isVideo).toList();

    expect(find.text('THIS IS WHAT WE SOUND LIKE'), findsOne);
    expect(find.text('CLIPS'), findsNothing);
    expect(find.text('PINNED'), findsOne);
    for (final video in videos) {
      expect(find.text(video.title), findsOne);
    }
    expect(find.byType(BandVideoThumbnail), findsNWidgets(videos.length));
  });

  testWidgets('profile banner is scrimmed, upright, and editable by admins', (
    tester,
  ) async {
    final harness = await _pumpProfile(tester);

    final scrim = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('band-profile-banner-scrim')),
    );
    final gradient = (scrim.decoration as BoxDecoration).gradient!;
    expect(gradient, isA<LinearGradient>());
    expect(
      (gradient as LinearGradient).colors.every((color) => color.a >= .58),
      isTrue,
    );
    expect(find.byKey(const ValueKey('band-profile-avatar-frame')), findsOne);
    expect(find.byType(BandIdentityHeader), findsOne);
    expect(find.text('486 followers'), findsOne);
    expect(find.text('PROFILE COMPLETE'), findsNothing);
    final edit = find.byKey(const ValueKey('edit-band-profile-banner'));
    expect(edit, findsOne);

    await tester.tap(edit);
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandEdit);
  });

  testWidgets('profile banner edit is hidden for a non-active managed band', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _MultiBandRepository(auth: auth),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    expect(harness.app.isAdminOf('b1'), isTrue);

    harness.app.switchToBand('b2');
    await tester.pumpAndSettle();

    expect(harness.app.bandId, 'b2');
    expect(
      find.byKey(const ValueKey('edit-band-profile-banner')),
      findsNothing,
    );
  });

  testWidgets('member preview is public-profile read-only', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _MemberRepository(auth: auth),
      beforePump: (app) => app.go(Screen.bandPreview, 'b1'),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('PUBLIC PROFILE PREVIEW'), findsOne);
    expect(find.text('Edit profile'), findsNothing);
    expect(
      find.byKey(const ValueKey('edit-band-profile-banner')),
      findsNothing,
    );
    expect(find.text('Return to band dashboard'), findsOne);

    harness.app.openBandEditor();
    expect(harness.app.current.screen, Screen.bandPreview);
  });

  testWidgets('profile renders all demo photo tiles', (tester) async {
    await _pumpProfile(tester);

    await tester.scrollUntilVisible(
      find.text('PHOTOS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
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
    final semantics = tester.ensureSemantics();
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
      find.byKey(const ValueKey('band-social-youtube')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    final links = [
      (
        key: const ValueKey('band-social-instagram'),
        label: 'Open Instagram',
        icon: BrandGlyph.instagram,
      ),
      (
        key: const ValueKey('band-social-bandcamp'),
        label: 'Open Bandcamp',
        icon: BrandGlyph.bandcamp,
      ),
      (
        key: const ValueKey('band-social-youtube'),
        label: 'Open YouTube',
        icon: BrandGlyph.youtube,
      ),
    ];
    for (final link in links) {
      final button = find.byKey(link.key);
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, 48);
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(find.byTooltip(link.label), findsOneWidget);
      expect(find.bySemanticsLabel(link.label), findsOneWidget);
      expect(find.byIcon(link.icon.data), findsOneWidget);
    }
    expect(find.text('INSTAGRAM ↗'), findsOne);
    expect(find.text('BANDCAMP ↗'), findsOne);
    expect(find.text('YOUTUBE ↗'), findsOne);
    semantics.dispose();
  });

  testWidgets('social icons wrap at narrow width and increased text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final harness = await _pumpProfile(tester);
    tester.view.physicalSize = const Size(170, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pump();
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

    final instagram = find.byKey(const ValueKey('band-social-instagram'));
    final bandcamp = find.byKey(const ValueKey('band-social-bandcamp'));
    final youtube = find.byKey(const ValueKey('band-social-youtube'));
    await tester.scrollUntilVisible(
      youtube,
      180,
      scrollable: find.byType(Scrollable).first,
    );

    for (final link in [instagram, bandcamp, youtube]) {
      final size = tester.getSize(link);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, lessThanOrEqualTo(138));
    }
    expect(
      tester.getTopLeft(bandcamp).dy,
      greaterThan(tester.getTopLeft(instagram).dy),
    );
    expect(
      tester.getTopLeft(youtube).dy,
      greaterThan(tester.getTopLeft(bandcamp).dy),
    );
  });
}

Future<AppHarness> _pumpProfile(WidgetTester tester) => pumpApp(
  tester,
  home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
);

class _MemberRepository extends DemoRepository {
  _MemberRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() => Stream.value([
    BandMembership(band: DemoData.bands['b1']!, role: 'member'),
  ]);
}

class _MultiBandRepository extends DemoRepository {
  _MultiBandRepository({required super.auth});

  @override
  Stream<List<BandMembership>> myBands() => Stream.value([
    BandMembership(band: DemoData.bands['b1']!, role: 'admin'),
    BandMembership(band: DemoData.bands['b2']!, role: 'admin'),
  ]);
}
