import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/screens/edit_profile.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/screens/home.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('Home list remains usable at increased text scale', (
    tester,
  ) async {
    await pumpApp(
      tester,
      beforePump: (app) => app.setMapMode(false),
      home: _scaledScreen(const HomeScreen()),
    );

    expect(find.text('LIST'), findsOne);
    expect(find.textContaining('GIGS NEAR YOU'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Explore remains usable at increased text scale', (tester) async {
    await pumpApp(tester, home: _scaledScreen(const ExploreScreen()));

    expect(find.text('Explore'), findsOne);
    final filters = find.byKey(const Key('explore-filter-button'));
    expect(filters, findsOne);
    expect(tester.getSize(filters), const Size(48, 48));
    expect(find.text('PUNK'), findsNothing);
    await tester.tap(filters);
    await tester.pumpAndSettle();
    expect(find.text('PUNK'), findsOne);
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
      home: _scaledScreen(const MyGigsScreen(), size: const Size(320, 900)),
    );
    tester.view.physicalSize = const Size(320, 900);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fan-following-stat')), findsOne);
    expect(find.byKey(const Key('fan-history-stat')), findsOne);
    for (final key in const [
      Key('edit-profile-action'),
      Key('share-fan-profile'),
      Key('profile-settings-action'),
    ]) {
      expect(find.byKey(key), findsOne);
      expect(tester.getSize(find.byKey(key)), const Size(48, 48));
    }
    expect(find.byTooltip('Edit profile'), findsOne);
    expect(find.byTooltip('Share profile summary'), findsOne);
    expect(find.byTooltip('Privacy and account settings'), findsOne);
    await tester.scrollUntilVisible(
      find.text('UPCOMING RSVPS'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('UPCOMING RSVPS'), findsOne);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fan-following-stat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('following-search-field')), findsOne);
    expect(find.text('FOLLOWING ✓'), findsWidgets);
    final followingButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'FOLLOWING ✓').first,
    );
    expect(
      followingButton.style!.textStyle!.resolve({})!.fontSize,
      greaterThanOrEqualTo(11),
    );
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
        home: _scaledScreen(
          const EditProfileScreen(),
          size: const Size(320, 900),
        ),
      );
      tester.view.physicalSize = const Size(320, 900);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fan-identity-preview')), findsOne);
      expect(find.byKey(const Key('fan-name-field')), findsOne);
      expect(find.byKey(const Key('fan-home-location-field')), findsOne);
      expect(find.byKey(const Key('save-fan-profile')), findsOne);

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
    await tester.tap(find.byKey(const Key('fan-history-stat')));
    await tester.pumpAndSettle();

    final qualificationFinder = find.byKey(qualificationKey);
    expect(find.text(qualification), findsWidgets);
    final text = tester.widget<Text>(qualificationFinder);
    final bounds = tester.getRect(qualificationFinder);
    expect(text.style!.fontSize, greaterThanOrEqualTo(11));
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(402));
    expect(bounds.bottom, greaterThan(0));
    expect(bounds.top, lessThan(900));
    expect(tester.takeException(), isNull);
  });
}

Widget _scaledScreen(Widget child, {Size size = const Size(402, 900)}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(1.5)),
    child: Scaffold(body: child),
  );
}
