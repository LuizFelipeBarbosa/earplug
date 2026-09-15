import 'dart:async';

import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/band_profile.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

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
      repository: _profileRepository(
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

    await tester.scrollUntilVisible(
      find.text('ABOUT'),
      250,
      scrollable: find.byType(Scrollable).first,
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
      find.text('AVERY STONE'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('BAND MEMBERS'), findsOne);
    expect(find.text('AVERY STONE'), findsOne);
    expect(find.text('JO RIVERA'), findsOne);
  });

  testWidgets('empty optional details leave no empty public sections', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _profileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    await tester.scrollUntilVisible(
      find.text('ABOUT'),
      250,
      scrollable: find.byType(Scrollable).first,
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
      repository: _profileRepository(
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

    await tester.scrollUntilVisible(
      find.text('ABOUT'),
      250,
      scrollable: find.byType(Scrollable).first,
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
    expect(find.text('EDIT PROFILE'), findsOne);
    expect(find.text('RETURN TO BAND DASHBOARD'), findsOne);

    await tester.tap(find.text('EDIT PROFILE'));
    await tester.pump();
    expect(harness.app.current.screen, Screen.bandEdit);

    harness.app.go(Screen.bandPreview, 'b1');
    await tester.pump();
    await tester.tap(find.text('RETURN TO BAND DASHBOARD'));
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

    expect(
      find.text('BAND · ${DemoData.bands['b1']!.area.toUpperCase()}'),
      findsNWidgets(2),
    );
    expect(find.text('PUBLIC PROFILE PREVIEW'), findsNothing);
    expect(find.text('RETURN TO BAND DASHBOARD'), findsNothing);
    expect(find.text('EDIT PROFILE'), findsNothing);
  });

  testWidgets('press hero keeps follow as the sole primary profile action', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.byKey(const ValueKey('band-profile-hero-b1')), findsOne);
    expect(find.text('FOLLOW'), findsNWidgets(2));
    final follow = find.byKey(const ValueKey('band-follow'));
    expect(follow, findsOneWidget);
    expect(tester.widget<EpPill>(follow).variant, EpPillVariant.primary);
    final miniFollow = find.byKey(const ValueKey('band-mini-follow'));
    expect(miniFollow, findsOneWidget);
    expect(tester.widget(miniFollow), isA<EpPill>());
  });

  testWidgets('share button copies the band public URL and shows a toast', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        if (call.method == 'Clipboard.getData') return {'text': copiedText};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpProfile(tester);

    await tester.tap(find.byKey(const ValueKey('band-share')));
    await tester.pump();

    final publicRef = DemoData.bands['b1']!.publicRef;
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Link copied: earplug.app/$publicRef'), findsOneWidget);
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, 'https://earplug.app/$publicRef');
  });

  testWidgets('pinned mini header appears only after scrolling past the hero', (
    tester,
  ) async {
    await _pumpProfile(tester);
    final miniHeader = find.byKey(const ValueKey('band-profile-mini-header'));
    final topBar = find.ancestor(
      of: find.byKey(
        const ValueKey('band-profile-back-control'),
        skipOffstage: false,
      ),
      matching: find.byType(AnimatedOpacity, skipOffstage: false),
    );
    expect(tester.getTopLeft(miniHeader).dy, greaterThan(200));
    expect(tester.widget<AnimatedOpacity>(topBar).opacity, 1);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(miniHeader).dy, closeTo(0, 1));
    expect(tester.widget<AnimatedOpacity>(topBar).opacity, 0);
  });

  testWidgets('ABOUT renders the stat grid and configured link rows', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: _profileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!.copyWith(
          linkIg: '@foghorn.diet',
          linkBc: 'foghorn.bandcamp.com',
          linkYt: 'youtube.com/@foghorn',
        ),
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    await tester.scrollUntilVisible(
      find.text('ABOUT'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    final stats = tester.widget<EpStatGrid>(find.byType(EpStatGrid)).stats;
    expect(stats.map((stat) => stat.value), [
      DemoData.bands['b1']!.followersLabel,
      '${harness.media.videosFor('b1').length}',
      '${harness.media.photosFor('b1').length}',
    ]);
    expect(find.text('FOLLOWERS'), findsOneWidget);
    expect(find.text('VIDEOS'), findsOneWidget);
    expect(find.text('PHOTOS'), findsOneWidget);
    for (final name in ['instagram', 'bandcamp', 'youtube']) {
      final link = find.byKey(ValueKey('band-social-$name'));
      expect(link, findsOneWidget);
      expect(tester.widget(link), isA<EpMenuRow>());
      expect(
        find.descendant(of: link, matching: find.text('↗')),
        findsOneWidget,
      );
    }
  });

  testWidgets('public profile keeps completion state private', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _profileRepository(
        auth: auth,
        profileBand: DemoData.bands['b1']!,
        details: BandProfileDetails.empty,
      ),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );
    expect(find.byKey(const Key('profile-complete-badge')), findsNothing);
    expect(find.textContaining('486 FOLLOWERS'), findsOne);

    await tester.pumpWidget(const SizedBox.shrink());
    final incompleteAuth = FakeAuthService();
    await pumpApp(
      tester,
      auth: incompleteAuth,
      repository: _profileRepository(
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
      repository: StubRepository(auth: auth)..returns('bandHistory', history),
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

  testWidgets('profile banner is scrimmed, upright, and editable by admins', (
    tester,
  ) async {
    final harness = await _pumpProfile(tester);

    final scrim = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('band-profile-banner-scrim')),
    );
    final gradient = (scrim.decoration as BoxDecoration).gradient!;
    expect(gradient, isA<LinearGradient>());
    final linear = gradient as LinearGradient;
    final hero = find.byKey(const ValueKey('band-profile-hero-b1'));
    expect(linear.begin, Alignment.bottomCenter);
    expect(linear.end, Alignment.topCenter);
    expect(linear.stops, [0, .6]);
    expect(linear.colors.first, tester.element(hero).epColors.background);
    expect(linear.colors.last.a, 0);
    expect(find.byKey(const ValueKey('band-profile-avatar-frame')), findsOne);
    expect(find.descendant(of: hero, matching: find.byType(EpPanel)), findsOne);
    final image = find.descendant(
      of: find.byKey(const ValueKey('band-profile-image-control')),
      matching: find.byType(EpNetworkImage),
    );
    expect(image, findsOneWidget);
    final avatar = tester.widget<EpAvatarTile>(
      find.descendant(of: hero, matching: find.byType(EpAvatarTile)),
    );
    expect(avatar.size, tester.getSize(hero).height);
    expect(tester.getSize(hero).height, 402);
    expect(avatar.accent, isTrue);
    expect(find.textContaining('486 FOLLOWERS'), findsOne);
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
      repository: _profileRepository(
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
      repository: _profileRepository(auth: auth, role: 'member'),
      beforePump: (app) => app.go(Screen.bandPreview, 'b1'),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    expect(find.text('PUBLIC PROFILE PREVIEW'), findsOne);
    expect(find.text('EDIT PROFILE'), findsNothing);
    expect(
      find.byKey(const ValueKey('edit-band-profile-banner')),
      findsNothing,
    );
    expect(find.text('RETURN TO BAND DASHBOARD'), findsOne);

    harness.app.openBandEditor();
    expect(harness.app.current.screen, Screen.bandPreview);
  });

  testWidgets('sound panel spans the page and stacks the pinned clip first', (
    tester,
  ) async {
    await _pumpProfile(tester);
    final header = find.text('THIS IS WHAT WE SOUND LIKE · 05 VIDEOS');
    await tester.scrollUntilVisible(
      header,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    final panel = find.ancestor(of: header, matching: find.byType(EpPanel));
    final pageRect = tester.getRect(find.byType(CustomScrollView));
    final panelRect = tester.getRect(panel);
    expect(tester.widget<EpPanel>(panel).striped, isTrue);
    expect(panelRect.left, pageRect.left);
    expect(panelRect.right, pageRect.right);
    expect(tester.getTopLeft(header).dx, pageRect.left + EpLayout.gutter);

    final videos = DemoData.b1Media.where((media) => media.isVideo).toList();
    final tiles = find.descendant(
      of: panel,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('band-clip-'),
      ),
    );
    expect(tiles, findsNWidgets(videos.length));
    expect(tester.widget(tiles.first).key, const ValueKey('band-clip-bm1'));
    expect(find.text('PINNED'), findsOneWidget);
    expect(
      find.descendant(of: tiles.first, matching: find.text('PINNED')),
      findsOneWidget,
    );
    for (var index = 0; index < videos.length; index++) {
      final rect = tester.getRect(tiles.at(index));
      expect(rect.left, pageRect.left + EpLayout.gutter);
      expect(rect.right, pageRect.right - EpLayout.gutter);
      expect(rect.width / rect.height, closeTo(16 / 9, .001));
      if (index > 0) {
        expect(
          rect.top,
          greaterThan(tester.getRect(tiles.at(index - 1)).bottom),
        );
      }
    }
  });

  testWidgets('a pinned clip moves ahead of earlier unpinned clips', (
    tester,
  ) async {
    final auth = FakeAuthService();
    final videos = DemoData.b1Media.where((media) => media.isVideo).toList();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('mediaFor', [
          for (final clip in videos) clip.copyWith(pinned: clip.id == 'bm3'),
        ]),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    final firstClip = find.byKey(const ValueKey('band-clip-bm3'));
    await tester.scrollUntilVisible(
      firstClip,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PINNED'), findsOneWidget);
    expect(
      find.descendant(of: firstClip, matching: find.text('PINNED')),
      findsOneWidget,
    );
    final displayOrder = ['bm3', 'bm1', 'bm2', 'bm4', 'bm5'];
    for (var index = 1; index < displayOrder.length; index++) {
      expect(
        tester
            .getTopLeft(
              find.byKey(ValueKey('band-clip-${displayOrder[index]}')),
            )
            .dy,
        greaterThan(
          tester
              .getTopLeft(
                find.byKey(ValueKey('band-clip-${displayOrder[index - 1]}')),
              )
              .dy,
        ),
      );
    }
  });

  testWidgets('a fallback first video is not tagged pinned', (tester) async {
    final auth = FakeAuthService();
    final clip = DemoData.b1Media.first.copyWith(pinned: false);
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)..returns('mediaFor', [clip]),
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    final header = find.text('THIS IS WHAT WE SOUND LIKE · 01 VIDEO');
    await tester.scrollUntilVisible(
      header,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(header, findsOneWidget);
    expect(find.byKey(ValueKey('band-clip-${clip.id}')), findsOneWidget);
    expect(find.text('PINNED'), findsNothing);
    expect(find.text('PHOTOS 00'), findsNothing);
  });

  for (final area in [
    'Berkeley, CA',
    ' Berkeley, Alameda, CA ',
    ' Berkeley ',
  ]) {
    testWidgets('clip captions use the band name and area suffix for "$area"', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final band = DemoData.bands['b1']!.copyWith(area: area);
      await pumpApp(
        tester,
        auth: auth,
        repository: _profileRepository(auth: auth, profileBand: band),
        home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
      );

      final caption = find.text(
        '${band.name} — ${DemoData.b1Media.first.title}',
      );
      await tester.scrollUntilVisible(
        caption,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(caption, findsOneWidget);
      expect(
        find.text(area.contains(',') ? 'REC · CA' : 'REC · BERKELEY'),
        findsNWidgets(5),
      );
    });
  }

  testWidgets('profile renders all demo photo tiles in a separate section', (
    tester,
  ) async {
    await _pumpProfile(tester);

    final header = find.text('PHOTOS 02');
    await tester.scrollUntilVisible(
      header,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(header, findsOneWidget);
    final photosSection = find.ancestor(
      of: header,
      matching: find.byType(SliverToBoxAdapter),
    );
    expect(
      find.descendant(
        of: photosSection,
        matching: find.textContaining('THIS IS WHAT WE SOUND LIKE'),
      ),
      findsNothing,
    );
    for (final photo in DemoData.b1Media.where(
      (media) => media.kind == MediaKind.photo,
    )) {
      final tile = find.byKey(ValueKey('band-photo-${photo.id}'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tile, findsOne);
      expect(
        find.descendant(of: photosSection, matching: tile),
        findsOneWidget,
      );
    }
  });

  for (final withPhoto in [false, true]) {
    testWidgets('no videos omit the sound panel (with photo: $withPhoto)', (
      tester,
    ) async {
      final auth = FakeAuthService();
      final photo = DemoData.b1Media.firstWhere((media) => !media.isVideo);
      await pumpApp(
        tester,
        auth: auth,
        repository: StubRepository(auth: auth)
          ..returns('mediaFor', <BandMedia>[if (withPhoto) photo]),
        home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
      );

      await tester.scrollUntilVisible(
        find.textContaining('UPCOMING · '),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('THIS IS WHAT WE SOUND LIKE'), findsNothing);
      expect(
        find.textContaining('PHOTOS '),
        withPhoto ? findsOneWidget : findsNothing,
      );
      if (withPhoto) {
        expect(find.text('PHOTOS 01'), findsOneWidget);
        expect(find.byKey(ValueKey('band-photo-${photo.id}')), findsOneWidget);
      }
    });
  }

  testWidgets('a processing clip stays on the profile and shows a toast', (
    tester,
  ) async {
    final harness = await _pumpProfile(tester);
    final clip = DemoData.b1Media.firstWhere(
      (media) => media.isVideo && !media.pinned,
    );
    final clipPanel = find.byKey(ValueKey('band-clip-${clip.id}'));
    await tester.scrollUntilVisible(
      clipPanel,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(clipPanel), alignment: 0.5);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: clipPanel, matching: find.text('PROCESSING')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: clipPanel, matching: find.text(clip.lenLabel)),
      findsNothing,
    );
    await tester.tap(clipPanel);
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

  for (final upcoming in [
    DemoData.bands['b1']!.upcoming,
    ['g2'],
  ]) {
    testWidgets(
      'upcoming renders shared event rows for ${upcoming.length} shows',
      (tester) async {
        final auth = FakeAuthService();
        final band = DemoData.bands['b1']!.copyWith(upcoming: upcoming);
        final harness = await pumpApp(
          tester,
          auth: auth,
          repository: _profileRepository(
            auth: auth,
            profileBand: band,
            feedGigs: [
              for (final id in upcoming)
                DemoData.gigs.firstWhere((gig) => gig.id == id),
            ],
          ),
          home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
        );
        final header = find.text(
          upcoming.length == 1 ? 'UPCOMING · 1 SHOW' : 'UPCOMING · 2 SHOWS',
        );
        await tester.scrollUntilVisible(
          header,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(header, findsOneWidget);
        double? previousBottom;
        for (final id in upcoming) {
          final row = find.byKey(ValueKey('fan-event-$id'));
          expect(row, findsOneWidget);
          final rect = tester.getRect(row);
          if (previousBottom != null) {
            expect(rect.top, greaterThanOrEqualTo(previousBottom));
          }
          previousBottom = rect.bottom;
          for (final action in ['save']) {
            expect(
              find.descendant(
                of: row,
                matching: find.byKey(ValueKey('$action-$id')),
              ),
              findsOneWidget,
            );
          }
          expect(find.byKey(ValueKey('ticket-action-$id')), findsNothing);
          expect(find.byKey(ValueKey('share-$id')), findsNothing);
        }

        final firstRow = find.byKey(ValueKey('fan-event-${upcoming.first}'));
        await Scrollable.ensureVisible(
          tester.element(firstRow),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: firstRow,
            matching: find.text(
              harness.app.gig(upcoming.first)!.title.toUpperCase(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(harness.app.current.screen, Screen.gig);
        expect(harness.app.current.param, upcoming.first);
      },
    );
  }

  testWidgets('empty upcoming section lets the fan follow the band', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final band = DemoData.bands['b1']!.copyWith(upcoming: const []);
    final repository = _profileRepository(
      auth: auth,
      profileBand: band,
      feedGigs: const [],
    );
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: BandProfileScreen(bandId: 'b1')),
    );

    final follow = find.byKey(const ValueKey('band-upcoming-follow'));
    await tester.scrollUntilVisible(
      follow,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('UPCOMING · 0 SHOWS'), findsOneWidget);
    final box = find.ancestor(of: follow, matching: find.byType(DashedBox));
    expect(box, findsOneWidget);
    expect(
      find.descendant(of: box, matching: find.text('NO SHOWS YET.')),
      findsOneWidget,
    );
    expect(
      find.text('Follow ${band.name} to hear about new dates.'),
      findsOneWidget,
    );
    expect(harness.app.follows, isNot(contains(band.id)));
    expect(tester.widget<EpPill>(follow).variant, EpPillVariant.primary);

    await Scrollable.ensureVisible(tester.element(follow), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(follow);
    await tester.pumpAndSettle();

    expect(repository.callsTo('toggleFollow'), 1);
    expect(harness.app.follows, contains(band.id));
    expect(tester.widget<EpPill>(follow).label, 'Following ✓');
    expect(tester.widget<EpPill>(follow).variant, EpPillVariant.ink);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'ABOUT link rows stay usable at narrow width and increased text scale',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final harness = await _pumpProfile(tester);
      tester.view.physicalSize = const Size(360, 1000);
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
        await Scrollable.ensureVisible(tester.element(link), alignment: 0.5);
        await tester.pumpAndSettle();
        final size = tester.getSize(link);
        expect(link, findsOneWidget);
        expect(size.height, greaterThanOrEqualTo(44));
        expect(size.width, lessThanOrEqualTo(360 - 2 * EpLayout.gutter));
        final row = tester.widget<EpMenuRow>(link);
        expect(row.onTap, isNotNull);
        expect(link.hitTestable(), findsOneWidget);
        expect(
          find.descendant(of: link, matching: find.text('↗')),
          findsOneWidget,
        );
      }
      expect(
        tester.getTopLeft(bandcamp).dy,
        greaterThan(tester.getTopLeft(instagram).dy),
      );
      expect(
        tester.getTopLeft(youtube).dy,
        greaterThan(tester.getTopLeft(bandcamp).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
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
StubRepository _profileRepository({
  required AuthService auth,
  Band? profileBand,
  BandProfileDetails? details,
  List<Gig>? feedGigs,
  String role = 'admin',
  List<String> managedBandIds = const ['b1'],
}) {
  final stub = StubRepository(auth: auth);
  if (profileBand != null) {
    stub.returnsStream(
      'feed',
      () => Stream.value(
        FeedSnapshot(
          gigs: feedGigs ?? DemoData.gigs,
          venues: DemoData.venues,
          bands: {...DemoData.bands, profileBand.id: profileBand},
        ),
      ),
    );
  }
  stub.returnsStream(
    'myBands',
    () => Stream.value([
      for (final id in managedBandIds)
        BandMembership(
          band: id == profileBand?.id ? profileBand! : DemoData.bands[id]!,
          role: role,
        ),
    ]),
  );
  if (details != null) stub.returns('bandProfileDetails', details);
  return stub;
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
