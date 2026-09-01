import 'package:earplug/data/demo_repository.dart';
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

  testWidgets('Profile remains usable at increased text scale', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: _scaledScreen(const MyGigsScreen()),
    );

    await tester.scrollUntilVisible(
      find.text('UPCOMING RSVPS'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('UPCOMING RSVPS'), findsOne);
    await tester.scrollUntilVisible(
      find.text('FOLLOWING'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('FOLLOWING ✓'), findsWidgets);
    final followingButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'FOLLOWING ✓').first,
    );
    expect(
      followingButton.style!.textStyle!.resolve({})!.fontSize,
      greaterThanOrEqualTo(11),
    );
    expect(tester.takeException(), isNull);
  });

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
    await tester.scrollUntilVisible(
      find.byKey(qualificationKey),
      240,
      scrollable: find.byType(Scrollable).first,
    );

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

Widget _scaledScreen(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(
      size: Size(402, 900),
      textScaler: TextScaler.linear(1.5),
    ),
    child: Scaffold(body: child),
  );
}
