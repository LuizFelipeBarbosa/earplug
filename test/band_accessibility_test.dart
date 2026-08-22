import 'package:earplug/screens/band_create.dart';
import 'package:earplug/screens/band_dash.dart';
import 'package:earplug/screens/band_edit.dart';
import 'package:earplug/screens/band_profile.dart';
import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/screens/gig_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  for (final screen in <(String, Widget)>[
    ('band dashboard', const BandDashScreen()),
    ('band profile editor', const BandEditScreen()),
    ('band profile', const BandProfileScreen(bandId: 'b1')),
    ('gig manager', const GigManagerScreen()),
  ]) {
    testWidgets('${screen.$1} is usable at increased text scale', (
      tester,
    ) async {
      await pumpApp(tester, home: _scaledScreen(screen.$2));

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
    });
  }

  testWidgets('band creation is usable at increased text scale', (
    tester,
  ) async {
    await pumpApp(
      tester,
      beforePump: (app) => app.startBandCreate(),
      home: _scaledScreen(const BandCreateScreen()),
    );

    expect(find.text('CREATE BAND'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gig creation is usable at increased text scale', (tester) async {
    await pumpApp(
      tester,
      beforePump: (app) => app.startGigCreate(),
      home: _scaledScreen(const GigCreateScreen()),
    );

    expect(find.text('PUBLISH GIG'), findsOne);
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
