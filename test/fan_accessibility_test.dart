import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/screens/edit_profile.dart';
import 'package:earplug/screens/explore.dart';
import 'package:earplug/screens/my_gigs.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/services/location_service.dart';
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
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('explore-default')),
      matching: find.byType(Scrollable),
    );
    for (final suffix in ['near-me', 'tonight', 'free']) {
      final row = find.byKey(Key('explore-suggest-$suffix'));
      await tester.scrollUntilVisible(row, 160, scrollable: scrollable);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    }
    final tonight = find.byKey(const Key('explore-suggest-tonight'));
    await tester.ensureVisible(tonight);
    await tester.tap(tonight);
    await tester.pumpAndSettle();
    // Demo shows start at 21:00; after that, tonight can have no future hits.
    expect(find.byKey(const Key('explore-results-meta')), findsOne);
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
      final avatarControl = tester.getSize(
        find.byKey(const Key('fan-avatar-preview-control')),
      );
      expect(avatarControl.width, greaterThanOrEqualTo(44));
      expect(avatarControl.height, greaterThanOrEqualTo(44));
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
      final locationSize = tester.getSize(
        find.byKey(const Key('use-current-home-location')),
      );
      expect(locationSize.width, greaterThanOrEqualTo(48));
      expect(locationSize.height, greaterThanOrEqualTo(48));

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

  for (final reason in [
    LocationFailureReason.servicesDisabled,
    LocationFailureReason.permissionDeniedForever,
  ]) {
    testWidgets('location recovery links retain touch targets for $reason', (
      tester,
    ) async {
      await pumpApp(
        tester,
        locationService: _RecoveryLocationService(reason),
        home: scaledScreen(
          const EditProfileScreen(),
          size: const Size(320, 900),
        ),
      );
      tester.view.physicalSize = const Size(320, 900);
      await tester.pumpAndSettle();
      final currentLocation = find.byKey(
        const Key('use-current-home-location'),
      );
      await tester.scrollUntilVisible(
        currentLocation,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(currentLocation);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-location-error')), findsOne);
      for (final key in const [
        Key('use-current-home-location'),
        Key('retry-current-home-location'),
        Key('open-home-location-settings'),
      ]) {
        final control = find.byKey(key);
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        expect(tester.widget(control), isA<TextButton>());
        final size = tester.getSize(control);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    });
  }

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

class _RecoveryLocationService implements LocationService {
  const _RecoveryLocationService(this.reason);

  final LocationFailureReason reason;

  @override
  Future<LocationResult> requestCurrentLocation() async =>
      LocationFailure(reason);

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}
