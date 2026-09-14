import 'package:earplug/main.dart';
import 'package:earplug/navigation.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  const phoneSize = Size(390, 844);
  const desktopSize = Size(1280, 900);

  Future<AppHarness> pumpRoute(
    WidgetTester tester, {
    required Size size,
    required Screen screen,
    String? param,
    double? topPadding,
  }) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    final harness = await pumpApp(
      tester,
      auth: auth,
      size: size,
      home: Builder(
        builder: (context) {
          const child = RootShell();
          if (topPadding == null) return child;
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: EdgeInsets.only(top: topPadding)),
            child: child,
          );
        },
      ),
    );
    harness.app.setMapMode(false);
    await tester.pumpAndSettle();
    if (screen != Screen.home) {
      harness.app.go(screen, param);
      await tester.pumpAndSettle();
    }
    return harness;
  }

  testWidgets('fan-facing first elements share the phone header offset', (
    tester,
  ) async {
    final routes = <({Screen screen, String? param, Finder first})>[
      (
        screen: Screen.home,
        param: null,
        first: find.byKey(const ValueKey('home-header-row')),
      ),
      (
        screen: Screen.explore,
        param: null,
        first: find.byType(EpDisplay).first,
      ),
      (
        screen: Screen.myGigs,
        param: null,
        first: find.byKey(const Key('fan-profile-title')),
      ),
      (
        screen: Screen.people,
        param: null,
        first: find.byKey(const ValueKey('people-back-control')),
      ),
      (
        screen: Screen.exploreCollection,
        param: 'tonight',
        first: find.byKey(const ValueKey('explore-collection-back-control')),
      ),
      (
        screen: Screen.gig,
        param: 'g1',
        first: find.byKey(const ValueKey('gig-detail-back-control')),
      ),
      (
        screen: Screen.band,
        param: 'b1',
        first: find.byKey(const ValueKey('band-profile-back-control')),
      ),
      (
        screen: Screen.venue,
        param: 'v1',
        first: find.byKey(const ValueKey('venue-detail-back-control')),
      ),
      (
        screen: Screen.settings,
        param: null,
        first: find.byKey(const ValueKey('settings-back-control')),
      ),
      (
        screen: Screen.editProfile,
        param: null,
        first: find.byKey(const ValueKey('edit-profile-header-row')),
      ),
    ];

    for (final route in routes) {
      await pumpRoute(
        tester,
        size: phoneSize,
        screen: route.screen,
        param: route.param,
        topPadding: 47,
      );
      final topLeft = tester.getTopLeft(route.first);
      expect(
        topLeft.dx,
        closeTo(EpLayout.gutter, 1),
        reason: route.screen.name,
      );
      expect(topLeft.dy, closeTo(47 + 22, 1), reason: route.screen.name);
    }
  });

  testWidgets('desktop tab headers start at the shared desktop offset', (
    tester,
  ) async {
    final routes = <({Screen screen, Finder first})>[
      (
        screen: Screen.home,
        first: find.byKey(const ValueKey('home-header-hero')),
      ),
      (screen: Screen.explore, first: find.byType(EpDisplay).first),
      (
        screen: Screen.myGigs,
        first: find.byKey(const Key('fan-profile-title')),
      ),
      (
        screen: Screen.people,
        first: find.byKey(const ValueKey('people-back-control')),
      ),
    ];

    for (final route in routes) {
      final harness = await pumpRoute(
        tester,
        size: desktopSize,
        screen: route.screen,
      );
      final topLeft = tester.getTopLeft(route.first);
      final shellLeft = tester
          .getTopLeft(find.byKey(const ValueKey('workspace-content')))
          .dx;
      expect(
        topLeft.dx,
        closeTo(shellLeft + 40 + EpLayout.gutter, 1),
        reason: route.screen.name,
      );
      expect(topLeft.dy, closeTo(28, 1), reason: route.screen.name);
      expect(harness.app.current.screen, route.screen);
    }
  });
}
