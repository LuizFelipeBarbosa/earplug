import 'package:earplug/demo_data.dart';
import 'package:earplug/screens/explore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('typing keeps a local draft until the search button is tapped', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      '  Mission Creep  ',
    );
    await tester.pump();

    expect(harness.app.query, isEmpty);
    expect(find.text('GENRES'), findsOne);

    await tester.tap(find.byKey(const Key('explore-search-submit')));
    await tester.pumpAndSettle();

    expect(harness.app.query, 'Mission Creep');
    expect(find.text('MISSION CREEP'), findsOne);
    expect(find.text('GENRES'), findsNothing);
  });

  testWidgets('keyboard search submits and clear restores browsing', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    await tester.enterText(
      find.byKey(const Key('explore-search-field')),
      'Foghorn',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(harness.app.query, 'Foghorn');
    expect(find.text('FOGHORN DIET'), findsOne);

    await tester.tap(find.byKey(const Key('explore-search-clear')));
    await tester.pumpAndSettle();

    expect(harness.app.query, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('explore-search-field')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('GENRES'), findsOne);
  });

  testWidgets('genre chips submit immediately', (tester) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: ExploreScreen()),
    );

    await tester.tap(find.text('PUNK'));
    await tester.pumpAndSettle();

    expect(harness.app.query, 'punk');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('explore-search-field')))
          .controller!
          .text,
      'punk',
    );
    expect(find.text('BANDS'), findsOne);
  });

  testWidgets('band and venue previews expand and collapse in place', (
    tester,
  ) async {
    await pumpApp(tester, home: const Scaffold(body: ExploreScreen()));

    final bandsToggle = find.byKey(const Key('explore-toggle-bands'));
    await tester.scrollUntilVisible(
      bandsToggle,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(DemoData.bands['b6']!.name.toUpperCase()), findsNothing);

    await tester.tap(bandsToggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-all-bands')), findsOne);
    expect(find.text(DemoData.bands['b6']!.name.toUpperCase()), findsOne);
    expect(find.text('SEE LESS BANDS'), findsOne);

    await tester.tap(bandsToggle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('explore-band-preview')), findsOne);
    expect(find.text('SEE ALL BANDS'), findsOne);

    final venuesToggle = find.byKey(const Key('explore-toggle-venues'));
    await tester.scrollUntilVisible(
      venuesToggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(DemoData.venues['v6']!.name.toUpperCase()), findsNothing);

    await tester.tap(venuesToggle);
    await tester.pumpAndSettle();

    expect(find.text(DemoData.venues['v6']!.name.toUpperCase()), findsOne);
    expect(find.text('SEE LESS VENUES'), findsOne);
  });
}
