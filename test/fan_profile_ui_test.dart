import 'package:earplug/app_state.dart';
import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/main.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/edit_profile.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/screens/settings.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/band_identity_editor.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/form_bits.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  testWidgets('profile fields use labelled form grammar and keep semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester, home: const Scaffold(body: EditProfileScreen()));
    tester.view.physicalSize = const Size(402, 3000);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fan-identity-preview')), findsOne);
    final editorPreview = tester.widget<Container>(
      find.byKey(const Key('fan-identity-preview')),
    );
    final editorDecoration = editorPreview.decoration! as BoxDecoration;
    expect(editorDecoration.color, Ep.surfaceRaised);
    expect(editorDecoration.gradient, isNull);
    expect(editorDecoration.border!.top.color, Ep.border);
    final previewName = tester.widget<Text>(
      find.byKey(const Key('fan-preview-name')),
    );
    final previewScene = tester.widget<Text>(
      find.byKey(const Key('fan-preview-scene')),
    );
    expect(previewName.style!.color, Ep.contentPrimary);
    expect(previewName.style!.fontSize, 25);
    expect(previewScene.style!.color, Ep.contentSecondary);
    expect(previewScene.style!.fontSize, 13);
    expect(find.bySemanticsLabel('Change profile image'), findsOne);
    expect(find.text('DISPLAY NAME · REQUIRED'), findsOne);
    expect(find.bySemanticsLabel('DISPLAY NAME · REQUIRED'), findsOne);
    expect(find.text('HOME LOCATION'), findsOne);
    expect(find.text('ABOUT'), findsOne);
    expect(find.bySemanticsLabel('ABOUT'), findsOne);
    expect(find.textContaining('FAVORITE GENRES'), findsOne);
    expect(find.text('PREFERENCES'), findsOne);
    expect(find.byType(BandIdentityTextField), findsNWidgets(2));
    expect(find.byType(StickyActionBar), findsOne);

    final orderedFields = [
      find.byKey(const Key('fan-identity-preview')),
      find.byKey(const Key('fan-name-field')),
      find.byKey(const Key('fan-home-location-field')),
      find.byKey(const Key('fan-bio-field')),
      find.byKey(const Key('fan-favorite-genres-field')),
      find.byKey(const Key('location-personalization')),
    ];
    for (var index = 1; index < orderedFields.length; index++) {
      expect(
        tester.getTopLeft(orderedFields[index]).dy,
        greaterThan(tester.getTopLeft(orderedFields[index - 1]).dy),
      );
    }
    for (final key in const [Key('fan-name-field'), Key('fan-bio-field')]) {
      final field = tester.widget<TextField>(find.byKey(key));
      expect(field.style!.fontFamily, 'Archivo Black');
      expect(field.decoration!.enabledBorder, isA<OutlineInputBorder>());
    }
    semantics.dispose();
  });

  testWidgets('home location autocompletes scenes and the current position', (
    tester,
  ) async {
    await pumpApp(
      tester,
      locationService: const _ProfileLocationService(),
      home: const Scaffold(body: EditProfileScreen()),
    );
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<FanCity>), findsNothing);
    expect(find.byKey(const Key('home-location-input')), findsOne);
    expect(FanCity.values.length, greaterThan(2));

    await tester.enterText(
      find.byKey(const Key('home-location-input')),
      'san j',
    );
    await tester.pump();
    expect(find.byKey(const Key('home-location-suggestion-sanJose')), findsOne);
    await tester.tap(find.byKey(const Key('home-location-suggestion-sanJose')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('home-location-input')))
          .controller!
          .text,
      'San Jose, CA',
    );

    await tester.tap(find.byKey(const Key('use-current-home-location')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('home-location-input')))
          .controller!
          .text,
      'Berkeley, CA',
    );
    expect(find.textContaining('nearest supported scene'), findsOne);
    expect(find.byKey(const Key('clear-home-location')), findsOne);
  });

  testWidgets('unknown home locations stay typed with a no-results state', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: EditProfileScreen()));
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('fan-name-field')),
      'Keep This Name',
    );
    await tester.enterText(
      find.byKey(const Key('home-location-input')),
      'Los Angeles',
    );
    await tester.pump();
    expect(find.byKey(const Key('home-location-no-results')), findsOne);

    await tester.tap(find.byKey(const Key('save-fan-profile')));
    await tester.pump();
    expect(find.byKey(const Key('home-location-validation')), findsOne);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('home-location-input')))
          .controller!
          .text,
      'Los Angeles',
    );
  });

  testWidgets('a failed location request keeps profile edits intact', (
    tester,
  ) async {
    await pumpApp(
      tester,
      locationService: const _FailedProfileLocationService(),
      home: const Scaffold(body: EditProfileScreen()),
    );
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('fan-name-field')),
      'Still Here',
    );
    await tester.enterText(
      find.byKey(const Key('home-location-input')),
      'San Mateo, California',
    );
    await tester.tap(find.byKey(const Key('use-current-home-location')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-location-error')), findsOne);
    expect(find.textContaining('not granted'), findsOne);
    expect(find.byKey(const Key('retry-current-home-location')), findsOne);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('fan-name-field')))
          .controller!
          .text,
      'Still Here',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('home-location-input')))
          .controller!
          .text,
      'San Mateo, California',
    );
  });

  testWidgets('identity preview edits and removes only the profile image', (
    tester,
  ) async {
    final picker = FakeMediaPicker()
      ..nextPhoto = photoFixture(filename: 'fan-avatar.png');
    await pumpApp(
      tester,
      home: Scaffold(body: EditProfileScreen(mediaPicker: picker)),
    );

    await tester.tap(find.byKey(const Key('fan-avatar-preview-control')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picked-fan-avatar-preview')), findsOne);
    expect(find.byKey(const Key('remove-fan-avatar')), findsOne);

    await tester.tap(find.byKey(const Key('remove-fan-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('picked-fan-avatar-preview')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('fan-identity-preview')),
        matching: find.byType(EpFanAvatar),
      ),
      findsOne,
    );
  });

  testWidgets('editor exposes only supported preferences in sticky form', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: EditProfileScreen()),
    );
    final barTop = tester.getTopLeft(find.byType(StickyActionBar)).dy;

    await tester.scrollUntilVisible(
      find.byKey(const Key('followed-band-updates')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
    await tester.pumpAndSettle();

    expect(find.byType(SwitchRow), findsNWidgets(2));
    expect(find.text('Personalize with home location'), findsOne);
    expect(find.text('Show followed-band updates'), findsOne);
    expect(find.textContaining('Your location stays private'), findsOne);
    expect(find.textContaining('bands you follow'), findsOne);
    expect(find.textContaining('going count'), findsNothing);
    expect(find.textContaining('reminder'), findsNothing);
    expect(tester.getTopLeft(find.byType(StickyActionBar)).dy, barTop);

    await tester.tap(find.text('Personalize with home location'));
    await tester.tap(find.text('Show followed-band updates'));
    await tester.tap(find.byKey(const Key('save-fan-profile')));
    await tester.pumpAndSettle();

    expect(harness.app.profile?.locationPersonalizationEnabled, isTrue);
    expect(harness.app.profile?.followedBandUpdatesEnabled, isFalse);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('fan-bio-field')))
          .maxLength,
      280,
    );
  });

  testWidgets('profile leads with private identity and branded fan fallback', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );

    expect(find.byKey(const Key('fan-profile-header')), findsOne);
    expect(find.byKey(const Key('fan-profile-avatar')), findsOne);
    expect(find.byType(EpFanAvatar), findsOne);
    expect(find.text('EF'), findsOne);
    expect(find.byKey(const Key('edit-profile-action')), findsOne);
    expect(find.byKey(const Key('share-fan-profile')), findsOne);
    expect(find.byKey(const Key('profile-settings-action')), findsOne);
    expect(find.byTooltip('Edit profile'), findsOne);
    expect(find.byTooltip('Share profile summary'), findsOne);
    expect(find.byTooltip('Privacy and account settings'), findsOne);
    expect(find.text('EDIT PROFILE'), findsNothing);
    expect(find.text('SHARE PROFILE'), findsNothing);
    expect(find.textContaining('SCENE'), findsOne);
    final profileHeader = tester.widget<Container>(
      find.byKey(const Key('fan-profile-header')),
    );
    final headerDecoration = profileHeader.decoration! as BoxDecoration;
    expect(headerDecoration.color, Ep.surfaceRaised);
    expect(headerDecoration.gradient, isNull);
    expect(headerDecoration.border!.top.color, Ep.border);
    final profileName = tester.widget<Text>(
      find.byKey(const Key('fan-profile-name')),
    );
    final profileScene = tester.widget<Text>(
      find.byKey(const Key('fan-profile-scene')),
    );
    expect(profileName.style!.color, Ep.contentPrimary);
    expect(profileName.style!.fontSize, 22);
    expect(profileScene.style!.color, Ep.contentSecondary);
    expect(profileScene.style!.fontSize, 13);
    final avatarFrame = tester.widget<Container>(
      find.byKey(const Key('fan-profile-avatar-frame')),
    );
    expect((avatarFrame.decoration! as BoxDecoration).color, Ep.border);
    final identityTop = tester
        .getTopLeft(find.byKey(const Key('fan-profile-header')))
        .dy;
    for (final key in const [
      Key('edit-profile-action'),
      Key('share-fan-profile'),
      Key('profile-settings-action'),
    ]) {
      final action = find.byKey(key);
      expect(tester.getSize(action), const Size(48, 48));
      expect(tester.getBottomLeft(action).dy, lessThanOrEqualTo(identityTop));
    }
    final followingValue = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('fan-following-stat')),
        matching: find.text('${harness.app.follows.length}'),
      ),
    );
    final historyValue = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('fan-history-stat')),
        matching: find.text('${harness.app.history.length}'),
      ),
    );
    expect(followingValue.style!.color, Ep.contentPrimary);
    expect(historyValue.style!.color, Ep.contentPrimary);
    expect(
      find.descendant(
        of: find.byKey(const Key('fan-following-stat')),
        matching: find.text('${harness.app.follows.length}'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('fan-history-stat')),
        matching: find.text('${harness.app.history.length}'),
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(
        'Following, ${harness.app.follows.length} '
        '${harness.app.follows.length == 1 ? 'band' : 'bands'}. '
        'Open followed bands.',
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(
        'RSVP History, ${harness.app.history.length} past '
        '${harness.app.history.length == 1 ? 'event' : 'events'}. '
        'Open RSVP history.',
      ),
      findsOne,
    );
    semantics.dispose();
  });

  testWidgets('profile sections stay in the required order', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: MyGigsScreen()));

    tester.view.physicalSize = const Size(402, 3000);
    await tester.pumpAndSettle();
    final positions = <Offset>[
      tester.getTopLeft(find.byKey(const Key('fan-profile-header'))),
    ];
    for (final label in [
      'UPCOMING RSVPS',
      'SAVED SHOWS',
      'UPCOMING SHOWS FROM FOLLOWED BANDS',
      'SETTINGS',
    ]) {
      positions.add(tester.getTopLeft(find.text(label)));
    }

    for (var index = 1; index < positions.length; index++) {
      expect(positions[index].dy, greaterThan(positions[index - 1].dy));
    }
    expect(find.text('EVENT HISTORY'), findsNothing);
    expect(find.byKey(const Key('history-qualification')), findsNothing);
  });

  testWidgets(
    'every empty profile section explains itself and offers a route',
    (tester) async {
      await pumpApp(tester, home: const Scaffold(body: MyGigsScreen()));

      tester.view.physicalSize = const Size(402, 3000);
      await tester.pumpAndSettle();
      expect(
        find.text('No upcoming RSVPs. Pick a show you want to catch.'),
        findsOne,
      );
      expect(
        find.text('Nothing saved. Bookmark a show to keep it handy.'),
        findsOne,
      );
      expect(
        find.text('Follow a band to see its upcoming shows here.'),
        findsOne,
      );
      expect(
        find.text('Follow bands to keep their profiles close.'),
        findsNothing,
      );
      expect(
        find.text('Past RSVPs will build your private event history.'),
        findsNothing,
      );
      expect(find.text('FIND A SHOW'), findsNWidgets(2));
      expect(find.text('EXPLORE BANDS'), findsOne);

      await tester.tap(find.byKey(const Key('fan-following-stat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fan-following-sheet')), findsOne);
      expect(find.byKey(const Key('following-search-field')), findsNothing);
      expect(find.text('Follow bands to keep their profiles close.'), findsOne);
      expect(find.text('EXPLORE BANDS'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Close Following'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fan-history-stat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fan-history-sheet')), findsOne);
      expect(
        find.text('Past RSVPs will build your private event history.'),
        findsOne,
      );
      expect(find.text('FIND A SHOW'), findsNWidgets(3));
    },
  );

  testWidgets('header statistics open complete private profile views', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );

    expect(find.byKey(const Key('history-qualification')), findsNothing);
    await tester.tap(find.byKey(const Key('fan-following-stat')));
    await tester.pumpAndSettle();

    final followingSheet = find.byKey(const Key('fan-following-sheet'));
    final search = find.byKey(const Key('following-search-field'));
    expect(followingSheet, findsOne);
    expect(search, findsOne);
    expect(find.bySemanticsLabel('Search followed bands'), findsOne);
    for (final bandId in harness.app.follows) {
      final band = harness.app.band(bandId);
      if (band != null) expect(find.text(band.name.toUpperCase()), findsOne);
    }
    final bandId = harness.app.follows.first;
    final band = harness.app.band(bandId)!;

    await tester.enterText(search, band.name);
    await tester.pump();
    expect(
      find.descendant(
        of: followingSheet,
        matching: find.text(band.name.toUpperCase()),
      ),
      findsOne,
    );
    await tester.tap(find.byKey(const Key('clear-following-search')));
    await tester.pump();

    await tester.enterText(search, band.genres.first);
    await tester.pump();
    expect(
      find.descendant(
        of: followingSheet,
        matching: find.text(band.name.toUpperCase()),
      ),
      findsOne,
    );
    await tester.tap(find.byKey(const Key('clear-following-search')));
    await tester.pump();

    await tester.enterText(search, band.area);
    await tester.pump();
    expect(
      find.descendant(
        of: followingSheet,
        matching: find.text(band.name.toUpperCase()),
      ),
      findsOne,
    );
    await tester.enterText(search, 'no-band-will-match-this');
    await tester.pump();
    expect(find.textContaining('No followed bands match'), findsOne);
    expect(find.text('CLEAR SEARCH'), findsOne);
    await tester.tap(find.text('CLEAR SEARCH'));
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: followingSheet,
        matching: find.text(band.name.toUpperCase()),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.app.current.screen, Screen.band);
    expect(harness.app.current.param, bandId);

    harness.app.back();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fan-history-stat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fan-history-sheet')), findsOne);
    expect(find.text('RSVP RECORD — ATTENDANCE NOT VERIFIED'), findsOne);
    for (final item in harness.app.history) {
      expect(find.text(item.title), findsOne);
    }
    semantics.dispose();
  });

  testWidgets('profile sharing includes counts but no event-level history', (
    tester,
  ) async {
    String? sharedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          sharedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );

    await tester.tap(find.byKey(const Key('share-fan-profile')));
    await tester.pump();

    expect(sharedText, contains('Following: ${harness.app.follows.length}'));
    expect(sharedText, contains('RSVP History: ${harness.app.history.length}'));
    expect(sharedText, contains('not verified attendance'));
    for (final item in harness.app.history) {
      expect(sharedText, isNot(contains(item.title)));
      if (item.venueName.isNotEmpty) {
        expect(sharedText, isNot(contains(item.venueName)));
      }
    }
    expect(find.text('Profile summary copied.'), findsOne);
  });

  testWidgets('long history titles and venues truncate in compact rows', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: _LongHistoryRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );
    tester.view.physicalSize = const Size(320, 700);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fan-history-stat')));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text(_longHistoryTitle));
    final venue = tester.widget<Text>(find.text(_longHistoryVenue));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(venue.maxLines, 1);
    expect(venue.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'revisiting Explore and Profile never promotes a past RSVP to upcoming',
    (tester) async {
      final now = DateTime(2026, 8, 31, 16);
      final auth = FakeAuthService();
      await auth.signInDemo();
      final repository = _MixedDateRsvpRepository(auth: auth, now: now);
      final harness = await pumpApp(
        tester,
        auth: auth,
        repository: repository,
        now: () => now,
        home: const RootShell(),
      );

      tester.view.physicalSize = const Size(402, 1400);
      for (var visit = 0; visit < 4; visit++) {
        await tester.tap(find.text('EXPLORE'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('PROFILE'));
        await tester.pumpAndSettle();
      }

      expect(harness.app.upcomingRsvpGigs.map((gig) => gig.id), [
        repository.futureGig.id,
      ]);
      expect(
        find.byKey(ValueKey('next-show-${repository.futureGig.id}')),
        findsOne,
      );
      expect(
        find.byKey(ValueKey('fan-event-${repository.pastGig.id}')),
        findsNothing,
      );
      expect(repository.pastGigPublicReads, 0);

      // A past gig can still be cached legitimately after opening a history
      // link. Its presence in the cache must not change its classification.
      expect(harness.app.gig(repository.pastGig.id), isNull);
      await tester.pumpAndSettle();
      harness.app.resetTo(Screen.myGigs);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('fan-event-${repository.pastGig.id}')),
        findsNothing,
      );
      expect(repository.pastGigPublicReads, 1);
    },
  );

  testWidgets('failed explicit save keeps edits on screen with an error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: _FailingProfileRepository(auth: auth),
      home: const Scaffold(body: EditProfileScreen()),
    );
    tester.view.physicalSize = const Size(402, 1800);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('fan-name-field')),
      'Changed Name',
    );
    await tester.enterText(
      find.byKey(const Key('home-location-input')),
      'BERKELEY, CA',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-fan-profile')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('save-fan-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edit-profile-error')), findsOne);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('fan-name-field')))
          .controller
          ?.text,
      'Changed Name',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('home-location-input')))
          .controller!
          .text,
      'BERKELEY, CA',
    );
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('followed-band shows open their gig details', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );
    final shows = harness.app.followedBandShows;
    expect(shows, isNotEmpty);
    final show = shows.firstWhere(
      (gig) =>
          !harness.app.rsvps.contains(gig.id) &&
          !harness.app.saved.contains(gig.id),
      orElse: () => shows.first,
    );

    tester.view.physicalSize = const Size(402, 5000);
    await tester.pumpAndSettle();
    final card = find.byKey(ValueKey('fan-event-${show.id}'));
    expect(card, findsOne);
    await tester.tap(card);
    await tester.pump();
    expect(harness.app.current.screen, Screen.gig);
    expect(harness.app.current.param, show.id);
  });

  testWidgets('failed unfollow rolls the Following row back', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _FailingFollowRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );
    tester.view.physicalSize = const Size(402, 4000);
    await tester.pumpAndSettle();

    expect(harness.app.follows, contains('b1'));
    await tester.tap(find.byKey(const Key('fan-following-stat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FOLLOWING ✓'));
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.toggleFollowCalls, 1);
    expect(harness.app.follows, contains('b1'));
    expect(find.text('FOLLOWING ✓'), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('profile tutorial completes and can be replayed from settings', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = DemoRepository(auth: auth);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      beforePump: (app) => app.resetTo(Screen.myGigs),
      home: const Scaffold(body: MyGigsScreen()),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('profile-tutorial')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('profile-tutorial')), findsOne);
    for (var step = 0; step < 3; step++) {
      final next = find.byKey(const Key('profile-tutorial-next'));
      tester.widget<FilledButton>(next).onPressed!();
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('profile-tutorial')), findsNothing);
    expect(harness.app.profile?.profileTutorialCompleted, isTrue);

    final replayHarness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: SettingsScreen()),
    );
    await tester.tap(find.byKey(const Key('replay-profile-tutorial')));
    await tester.pumpAndSettle();
    expect(replayHarness.app.current.screen, Screen.myGigs);
    expect(replayHarness.app.profileTutorialVisible, isTrue);
  });

  testWidgets('next in-app RSVP is promoted only out of upcoming section', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 31, 16);
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _MixedDateRsvpRepository(auth: auth, now: now);
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      now: () => now,
      home: const Scaffold(body: MyGigsScreen()),
    );

    tester.view.physicalSize = const Size(402, 3000);
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('next-show-${repository.futureGig.id}')),
      findsOne,
    );
    expect(
      find.byKey(ValueKey('fan-event-${repository.futureGig.id}')),
      findsNothing,
    );
    expect(find.text('QR PASS'), findsOne);
    expect(harness.app.upcomingRsvpGigs, contains(repository.futureGig));
  });

  testWidgets('legacy backend payload hides unsupported tutorial controls', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final repository = _LegacyProfileRepository(auth: auth);
    final profileHarness = await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: MyGigsScreen()),
    );

    expect(profileHarness.app.profileTutorialAvailable, isFalse);
    expect(find.byKey(const Key('profile-tutorial')), findsNothing);

    await pumpApp(
      tester,
      auth: auth,
      repository: repository,
      home: const Scaffold(body: SettingsScreen()),
    );
    expect(find.byKey(const Key('replay-profile-tutorial')), findsNothing);
  });

  testWidgets('settings separates destructive controls and protects deletion', (
    tester,
  ) async {
    final auth = FakeAuthService()..deleteAccountError = StateError('Clerk');
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: SettingsScreen()),
    );
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('delete-account')),
      240,
      scrollable: scrollable,
    );

    final signOut = tester.widget<OutlinedButton>(
      find.byKey(const Key('settings-sign-out')),
    );
    expect(signOut.style!.foregroundColor!.resolve({}), Ep.destructive);
    expect(find.byKey(const Key('account-danger-zone')), findsOne);

    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-delete-account')));
    await tester.pumpAndSettle();
    expect(auth.deleteAccountCalls, 0);

    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    var confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-delete-account')),
    );
    expect(confirm.onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    confirm = tester.widget(find.byKey(const Key('confirm-delete-account')));
    expect(confirm.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();

    expect(auth.deleteAccountCalls, 1);
    expect(harness.app.authed, isTrue);
    expect(find.byKey(const Key('delete-account-error')), findsOne);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('confirmed account deletion returns to signed-out home', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: SettingsScreen()),
    );
    tester.view.physicalSize = const Size(402, 1300);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete-account')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();

    expect(auth.deleteAccountCalls, 1);
    expect(harness.app.authed, isFalse);
    expect(harness.app.current.screen, Screen.home);
    expect(find.byKey(const Key('delete-account-error')), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}

const _longHistoryTitle =
    'A Very Long Event Name That Must Stay Inside The Compact History Card';
const _longHistoryVenue =
    'The Extremely Long Independent Venue Name Near The End Of The Street';

class _LongHistoryRepository extends DemoRepository {
  _LongHistoryRepository({required super.auth});

  @override
  Future<List<FanHistoryItem>> history() async => [
    FanHistoryItem(
      gigId: 'long-history',
      title: _longHistoryTitle,
      startsAt: DateTime(2026, 1, 2, 20),
      venueName: _longHistoryVenue,
      bandNames: const [],
      flyKey: 'paper',
      flyerUrl: null,
      status: FanHistoryStatus.rsvped,
    ),
  ];
}

class _FailingProfileRepository extends DemoRepository {
  _FailingProfileRepository({required super.auth});

  @override
  Future<void> updateFanProfile({
    required String name,
    required String? bio,
    required FanCity? homeLocation,
    required List<String> genres,
    required bool locationPersonalizationEnabled,
    required bool followedBandUpdatesEnabled,
  }) async {
    throw StateError('profile update failed');
  }
}

class _ProfileLocationService implements LocationService {
  const _ProfileLocationService();

  @override
  Future<LocationResult> requestCurrentLocation() async =>
      const LocationSuccess(
        UserLocation(
          latitude: 37.8717,
          longitude: -122.2728,
          accuracyMeters: 6,
        ),
      );

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _FailedProfileLocationService implements LocationService {
  const _FailedProfileLocationService();

  @override
  Future<LocationResult> requestCurrentLocation() async =>
      const LocationFailure(LocationFailureReason.permissionDenied);

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

class _MixedDateRsvpRepository extends DemoRepository {
  _MixedDateRsvpRepository({required super.auth, required DateTime now})
    : pastGig = _rsvpGig(
        id: 'past-rsvp',
        title: 'Past RSVP',
        startsAt: now.subtract(const Duration(days: 30)),
      ),
      futureGig = _rsvpGig(
        id: 'future-rsvp',
        title: 'Future RSVP',
        startsAt: now.add(const Duration(days: 30)),
      );

  final Gig pastGig;
  final Gig futureGig;
  int pastGigPublicReads = 0;

  @override
  Stream<Interactions> myInteractions() => Stream.value(
    Interactions(
      rsvpGigIds: {pastGig.id, futureGig.id},
      followBandIds: const {},
      savedGigIds: const {},
      gigs: [futureGig],
      attendedCount: 1,
    ),
  );

  @override
  Stream<Gig?> publicGig(String ref) {
    if (ref == pastGig.id) {
      pastGigPublicReads++;
      return Stream.value(pastGig);
    }
    return super.publicGig(ref);
  }
}

Gig _rsvpGig({
  required String id,
  required String title,
  required DateTime startsAt,
}) => Gig(
  id: id,
  title: title,
  venueId: 'v1',
  price: 0,
  startsAt: startsAt,
  dateShort: Gig.dateShortFor(startsAt.millisecondsSinceEpoch),
  dateLine: Gig.dateLineFor(startsAt.millisecondsSinceEpoch, '7PM / 8PM'),
  time: '7PM / 8PM',
  when: Gig.whenFor(startsAt.millisecondsSinceEpoch),
  flyKey: 'paper',
  lineup: const [],
  going: 1,
  genres: const ['indie'],
  desc: '',
  tix: Ticketing.rsvp,
);

class _LegacyProfileRepository extends DemoRepository {
  _LegacyProfileRepository({required super.auth});

  @override
  Future<UserProfile?> me() async => UserProfile.fromJson({
    'name': 'Legacy Fan',
    'email': 'legacy@example.com',
    'genres': <String>[],
    'attendedCount': 0,
    'createdAt': 1234,
  });
}

class _FailingFollowRepository extends DemoRepository {
  _FailingFollowRepository({required super.auth});

  var toggleFollowCalls = 0;

  @override
  Stream<Interactions> myInteractions() => Stream.value(
    const Interactions(
      rsvpGigIds: {},
      followBandIds: {'b1'},
      savedGigIds: {},
      attendedCount: 0,
    ),
  );

  @override
  Future<void> toggleFollow(String bandId) async {
    toggleFollowCalls++;
    throw StateError('follow update failed');
  }
}
