import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/screens/edit_profile.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/tab_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/accessibility.dart';
import 'support/harness.dart';

void main() {
  testWidgets('bottom tab bar accommodates accessibility text scale', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const MediaQuery(
        data: MediaQueryData(
          size: Size(402, 900),
          textScaler: TextScaler.linear(2),
        ),
        child: Scaffold(bottomNavigationBar: FanTabBar()),
      ),
    );

    final tabBarRow = find.descendant(
      of: find.byType(FanTabBar),
      matching: find.byType(Row),
    );
    expect(tester.getSize(tabBarRow).height, greaterThan(66));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explore remains usable at increased text scale', (tester) async {
    await pumpApp(tester, home: scaledScreen(const ExploreScreen()));

    expect(find.text('EXPLORE'), findsOne);
    final search = find.byKey(const Key('explore-search-field'));
    expect(search, findsOne);
    expect(tester.getSize(search).width, greaterThan(0));
    await tester.scrollUntilVisible(
      find.byKey(const Key('explore-genre-punk')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('explore-genre-rail-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.byKey(const Key('explore-genre-punk')), findsOne);
    final forYou = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'explore-for-you-',
          ),
    );
    final browseState = tester.state<ScrollableState>(_browseScrollable());
    browseState.position.jumpTo(0);
    await tester.pump();
    // The featured carousel wraps at this scale, so no row is built yet;
    // page down until the lazy list has built one, then bring it on screen.
    for (var step = 0; step < 12 && forYou.evaluate().isEmpty; step++) {
      browseState.position.jumpTo(browseState.position.pixels + 240);
      await tester.pump();
    }
    await tester.ensureVisible(forYou.first);
    await tester.pumpAndSettle();
    final rowSize = tester.getSize(forYou.first);
    expect(rowSize.width, greaterThanOrEqualTo(44));
    expect(rowSize.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Profile remains usable when narrow with increased text scale', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: scaledScreen(const MyGigsScreen(), size: const Size(320, 900)),
    );
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpAndSettle();

    expect(find.byType(EpStatGrid), findsOne);
    expect(find.byType(EpSegmentTabs), findsOne);
    for (final key in const [
      Key('edit-profile-action'),
      Key('profile-settings-action'),
    ]) {
      expect(tester.getSize(find.byKey(key)), const Size(44, 44));
    }
    expect(find.byTooltip('Edit profile'), findsOne);
    expect(find.byTooltip('Privacy and account settings'), findsOne);
    final browse = find.byKey(const Key('fan-stat-following'));
    await tester.ensureVisible(browse);
    await tester.pumpAndSettle();
    await tester.tap(browse);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('following-search-field')), findsOne);
    final sheet = find.byKey(const Key('fan-following-sheet'));
    expect(
      find.descendant(of: sheet, matching: find.byType(EpEntityRow)),
      findsWidgets,
    );
    final followingButton = tester.widget<EpPill>(
      find
          .descendant(
            of: sheet,
            matching: find.byWidgetPredicate(
              (widget) => widget is EpPill && widget.label == 'Following ✓',
            ),
          )
          .first,
    );
    expect(followingButton.onPressed, isNotNull);
    await tester.tap(find.byTooltip('Close Following'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Edit Profile remains usable when narrow at increased text scale',
    (tester) async {
      final auth = FakeAuthService();
      await auth.signInDemo();
      await pumpApp(
        tester,
        auth: auth,
        repository: DemoRepository(auth: auth),
        home: scaledScreen(
          const EditProfileScreen(),
          size: const Size(320, 900),
        ),
      );
      tester.view.physicalSize = const Size(320, 900);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fan-identity-preview')), findsOne);
      expect(find.byKey(const Key('fan-name-field')), findsOne);
      expect(find.byKey(const Key('save-fan-profile')), findsOne);

      await tester.scrollUntilVisible(
        find.byKey(const Key('fan-home-location-field')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('fan-home-location-field')), findsOne);

      await tester.scrollUntilVisible(
        find.byKey(const Key('use-current-home-location')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('use-current-home-location')))
            .height,
        greaterThanOrEqualTo(48),
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('fan-bio-field')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('fan-bio-field')), findsOne);
      await tester.scrollUntilVisible(
        find.byKey(const Key('fan-favorite-genres-field')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('fan-favorite-genres-field')), findsOne);
      await tester.scrollUntilVisible(
        find.byKey(const Key('followed-band-updates')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('location-personalization')), findsOne);
      expect(find.byKey(const Key('followed-band-updates')), findsOne);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Profile visibly qualifies RSVP history at phone width', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: const Scaffold(body: MyGigsScreen()),
    );

    const qualification = 'RSVP RECORD — ATTENDANCE NOT VERIFIED';
    const qualificationKey = Key('history-qualification');
    final past = find.byKey(const Key('fan-stat-history'));
    await tester.ensureVisible(past);
    await tester.tap(past);
    await tester.pumpAndSettle();

    final qualificationFinder = find.byKey(qualificationKey);
    await tester.ensureVisible(qualificationFinder);
    await tester.pumpAndSettle();
    expect(find.text(qualification), findsOne);
    final text = tester.widget<Text>(
      find.descendant(of: qualificationFinder, matching: find.byType(Text)),
    );
    final bounds = tester.getRect(qualificationFinder);
    expect(text.style!.fontSize, greaterThanOrEqualTo(11));
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(402));
    expect(bounds.bottom, greaterThan(0));
    expect(bounds.top, lessThan(900));
    expect(tester.takeException(), isNull);
  });
}

Finder _browseScrollable() => find
    .descendant(
      of: find.byKey(const ValueKey('explore-browse-all')),
      matching: find.byType(Scrollable),
    )
    .first;
