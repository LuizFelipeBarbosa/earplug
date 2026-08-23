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

    expect(find.text('SEARCH & EXPLORE'), findsOne);
    expect(find.text('PUNK'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My Gigs remains usable at increased text scale', (tester) async {
    final auth = FakeAuthService();
    await auth.signInDemo();
    await pumpApp(
      tester,
      auth: auth,
      repository: DemoRepository(auth: auth),
      home: _scaledScreen(const MyGigsScreen()),
    );

    expect(find.text("UPCOMING — YOU'RE GOING"), findsOne);
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
