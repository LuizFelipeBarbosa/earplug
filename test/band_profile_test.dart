import 'dart:async';

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

  testWidgets('public profile renders optional details only when present', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!.copyWith(
          linkIg: '@foghorn.diet',
          linkBc: 'foghorn.bandcamp.com',
          linkYt: 'youtube.com/@foghorn',
        ),
        details: const BandProfileDetails(
          credits: 'Recorded by Jo Rivera at Room Tone.',
          memberNames: ['Avery Stone', 'Jo Rivera'],
        ),
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-social-instagram')), findsOneWidget);
    expect(find.byKey(const ValueKey('band-social-bandcamp')), findsOneWidget);
    expect(find.byKey(const ValueKey('band-social-youtube')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recorded by Jo Rivera at Room Tone.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('CREDITS'), findsOne);
    expect(find.text('Recorded by Jo Rivera at Room Tone.'), findsOne);
    await tester.scrollUntilVisible(
      find.text('Avery Stone'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BAND MEMBERS'), findsOne);
    expect(find.text('Avery Stone'), findsOne);
    expect(find.text('Jo Rivera'), findsOne);
  });

  testWidgets('empty optional details leave no empty public sections', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-social-instagram')), findsNothing);
    expect(find.byKey(const ValueKey('band-social-bandcamp')), findsNothing);
    expect(find.byKey(const ValueKey('band-social-youtube')), findsNothing);
    expect(find.text('CREDITS'), findsNothing);
    expect(find.text('BAND MEMBERS'), findsNothing);
  });

  testWidgets('public profile renders only configured social icons', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!.copyWith(
          linkIg: '@foghorn.diet',
          linkBc: '',
          linkYt: '',
        ),
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-social-instagram')), findsOneWidget);
    expect(find.byKey(const ValueKey('band-social-bandcamp')), findsNothing);
    expect(find.byKey(const ValueKey('band-social-youtube')), findsNothing);
  });

  testWidgets('admin preview has edit and return management controls', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      beforePump: (app) => app.go(Screen.bandPreview, 'b1'),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('PUBLIC PROFILE PREVIEW'), findsOne);
    expect(find.text('Edit profile'), findsOne);
    expect(find.text('Return to band dashboard'), findsOne);

    await tester.tap(find.text('Edit profile'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandEdit);

    harness.app.go(Screen.bandPreview, 'b1');
    await tester.pump();
    await tester.tap(find.text('Return to band dashboard'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandDash);
  });

  testWidgets('member preview can return but cannot edit', (tester) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
        role: 'member',
      ),
      beforePump: (app) => app.go(Screen.bandPreview, 'b1'),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('PUBLIC PROFILE PREVIEW'), findsOne);
    expect(find.text('Return to band dashboard'), findsOne);
    expect(find.text('Edit profile'), findsNothing);

    await tester.tap(find.text('Return to band dashboard'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandDash);
  });

  testWidgets('ordinary visits retain the regular public header', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('BAND'), findsOne);
    expect(find.text('PUBLIC PROFILE PREVIEW'), findsNothing);
    expect(find.text('Return to band dashboard'), findsNothing);
    expect(find.text('Edit profile'), findsNothing);
  });

  testWidgets('press hero keeps follow as the sole primary profile action', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-profile-hero-b1')), findsOne);
    expect(find.textContaining('FOLLOW ·'), findsOne);
    expect(find.byType(FilledButton), findsOne);
  });

  testWidgets('public profile keeps completion state private', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ProfileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    expect(find.byKey(const Key('profile-complete-badge')), findsNothing);
    expect(find.text('486 followers'), findsOne);

    await tester.pumpWidget(const SizedBox.shrink());
    final incompleteAuth = FakeAuthService();
    await pumpApp(
      tester,
      auth: incompleteAuth,
      repository: _ProfileRepository(
        auth: incompleteAuth,
        profileBand: DemoData.bands['b1']!.copyWith(profileComplete: false),
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    expect(find.byKey(const Key('profile-complete-badge')), findsNothing);
  });

  testWidgets('live history replaces legacy past-show strings', (tester) async {
    final auth = FakeAuthService();
    final history = BandHistory(
      gigs: [DemoData.gigs[1], DemoData.gigs[0]],
      venues: {'v1': DemoData.venues['v1']!, 'v3': DemoData.venues['v3']!},
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: _HistoryRepository(auth: auth, stagedHistory: history),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await tester.scrollUntilVisible(
      find.text('PAST GIGS · 2 PLAYED'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PAST GIGS · 2 PLAYED', skipOffstage: false), findsOne);
    expect(
      find.textContaining(
        'Riptide Release Show · The Foghorn Club',
        skipOffstage: false,
      ),
      findsOne,
    );
    expect(
      find.textContaining('Basement Blowout · Casa Quake', skipOffstage: false),
      findsOne,
    );
    expect(
      find.text('Riptide warmup — Casa Quake', skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('demo history falls back to legacy past shows', (tester) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await tester.scrollUntilVisible(
      find.text('PAST GIGS · 4 PLAYED'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PAST GIGS · 4 PLAYED', skipOffstage: false), findsOne);
    for (final show in DemoData.bands['b1']!.past) {
      await tester.scrollUntilVisible(
        find.textContaining(show.title),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining(show.title, skipOffstage: false), findsOne);
    }
  });

  testWidgets('empty history without legacy rows is a quiet normal state', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _BareBandRepository(auth: auth),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await _scrollToPastGigs(tester);
    expect(find.text('No past shows yet.', skipOffstage: false), findsOne);
    expect(find.text('PAST GIGS', skipOffstage: false), findsOne);
    expect(find.text('RETRY', skipOffstage: false), findsNothing);
  });

  testWidgets('history failure waits for RETRY and then renders', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final repository = _BareBandRepository(
      auth: auth,
      failuresRemaining: 1,
      stagedHistory: BandHistory(
        gigs: [DemoData.gigs[0]],
        venues: {'v3': DemoData.venues['v3']!},
      ),
    );
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await _scrollToPastGigs(tester);
    expect(
      find.text("Couldn't load past shows.", skipOffstage: false),
      findsOne,
    );
    expect(repository.calls, 1);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(repository.calls, 1);

    final retry = find.text('RETRY', skipOffstage: false);
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    await tester.scrollUntilVisible(
      find.textContaining('Basement Blowout · Casa Quake'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('Basement Blowout · Casa Quake', skipOffstage: false),
      findsOne,
    );
    expect(
      find.text("Couldn't load past shows.", skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('history shows loading while its first request is gated', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final gate = Completer<void>();
    final repository = _BareBandRepository(auth: auth, gate: gate);
    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
      pumpFor: Duration.zero,
    );
    await tester.pump();

    await _scrollToPastGigs(tester);
    expect(find.text('Loading past shows…', skipOffstage: false), findsOne);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('No past shows yet.', skipOffstage: false), findsOne);
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
      repository: _ProfileRepository(
        auth: auth,
        managedBandIds: const ['b1', 'b2'],
      ),
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
      repository: _ProfileRepository(auth: auth, role: 'member'),
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
    await _saveSocialLinks(harness);
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
      expect(
        find.byWidgetPredicate(
          (widget) => widget is BrandIcon && widget.glyph == link.icon,
        ),
        findsOneWidget,
      );
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
    await _saveSocialLinks(harness);
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

Future<void> _saveSocialLinks(AppHarness harness) async {
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
}

Future<void> _scrollToPastGigs(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('PAST GIGS'),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// Demo data with the viewer's memberships fixed, optionally with one band
/// swapped into the feed and its profile details stubbed.
class _ProfileRepository extends DemoRepository {
  _ProfileRepository({
    required super.auth,
    this.profileBand,
    this.details,
    this.role = 'admin',
    this.managedBandIds = const ['b1'],
  });

  final Band? profileBand;
  final BandProfileDetails? details;
  final String role;
  final List<String> managedBandIds;

  @override
  Stream<FeedSnapshot> feed() {
    final band = profileBand;
    if (band == null) return super.feed();
    return Stream.value(
      FeedSnapshot(
        gigs: DemoData.gigs,
        venues: DemoData.venues,
        bands: {...DemoData.bands, band.id: band},
      ),
    );
  }

  @override
  Stream<List<BandMembership>> myBands() => Stream.value([
    for (final id in managedBandIds)
      BandMembership(
        band: id == profileBand?.id ? profileBand! : DemoData.bands[id]!,
        role: role,
      ),
  ]);

  @override
  Future<BandProfileDetails> bandProfileDetails(String bandId) async =>
      details ?? await super.bandProfileDetails(bandId);
}

class _HistoryRepository extends DemoRepository {
  _HistoryRepository({
    required super.auth,
    this.stagedHistory = BandHistory.empty,
  });

  final BandHistory stagedHistory;
  int calls = 0;

  @override
  Future<BandHistory> bandHistory(String bandId) async {
    calls++;
    return stagedHistory;
  }
}

class _BareBandRepository extends DemoRepository {
  _BareBandRepository({
    required super.auth,
    this.stagedHistory = BandHistory.empty,
    this.failuresRemaining = 0,
    this.gate,
  });

  final BandHistory stagedHistory;
  int failuresRemaining;
  final Completer<void>? gate;
  int calls = 0;

  static final _bareBand = Band(
    id: DemoData.bands['b1']!.id,
    name: DemoData.bands['b1']!.name,
    genres: DemoData.bands['b1']!.genres,
    area: DemoData.bands['b1']!.area,
    color: DemoData.bands['b1']!.color,
    initials: DemoData.bands['b1']!.initials,
    followers: DemoData.bands['b1']!.followers,
    bio: DemoData.bands['b1']!.bio,
    linkIg: DemoData.bands['b1']!.linkIg,
    linkBc: DemoData.bands['b1']!.linkBc,
    heroUrl: DemoData.bands['b1']!.heroUrl,
    past: const [],
  );

  @override
  Stream<FeedSnapshot> feed() => Stream.value(
    FeedSnapshot(gigs: const [], venues: const {}, bands: {'b1': _bareBand}),
  );

  @override
  Stream<List<BandMembership>> myBands() => const Stream.empty();

  @override
  Future<List<Band>> searchBands(String q) async => [_bareBand];

  @override
  Future<BandHistory> bandHistory(String bandId) async {
    calls++;
    await gate?.future;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw Exception('band history failed');
    }
    return stagedHistory;
  }
}
