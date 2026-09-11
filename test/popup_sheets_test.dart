import 'package:earplug/screens/home.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_sheet.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  for (final (size, textScale) in [
    (const Size(390, 844), 1.0),
    (const Size(360, 800), 1.5),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets('filter actions stay reachable at $size with $textScale text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final harness = await pumpApp(
        tester,
        home: const Scaffold(body: HomeScreen()),
        size: size,
      );
      await tester.tap(find.text('FILTERS'));
      await tester.pumpAndSettle();

      final options = find.descendant(
        of: find.byKey(const Key('discovery-filter-options')),
        matching: find.byType(Scrollable),
      );
      final clear = find.byKey(const Key('clear-discovery-filters'));
      final results = find.byKey(const Key('show-filter-results'));
      final clearPosition = tester.getRect(clear);
      final resultsPosition = tester.getRect(results);

      await tester.scrollUntilVisible(
        find.text('PUNK'),
        160,
        scrollable: options,
      );
      await tester.tap(find.text('PUNK'));
      await tester.pumpAndSettle();
      expect(harness.app.fGenres, {'punk'});

      await tester.scrollUntilVisible(
        find.text('PAID'),
        200,
        scrollable: options,
      );
      expect(tester.getRect(clear), clearPosition);
      expect(tester.getRect(results), resultsPosition);
      expect(clear.hitTestable(), findsOneWidget);
      expect(results.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Clear all resets the filters and results closes the sheet', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(body: HomeScreen()),
    );
    await tester.tap(find.text('FILTERS'));
    await tester.pumpAndSettle();
    expect(find.byType(EpSheetShell), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('PUNK'));
    await tester.pumpAndSettle();
    expect(harness.app.activeFilterCount, 1);
    await tester.tap(find.byKey(const Key('clear-discovery-filters')));
    await tester.pumpAndSettle();
    expect(harness.app.activeFilterCount, 0);

    await tester.tap(find.byKey(const Key('show-filter-results')));
    await tester.pumpAndSettle();
    expect(find.byType(EpSheetShell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long popup forms scroll above the keyboard without losing input',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final input = TextEditingController();
      addTearDown(input.dispose);
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEpTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEpSheet(
                  context,
                  (context) => EpFormSheet(
                    title: 'EDIT NOTES',
                    child: Column(
                      children: [
                        TextField(controller: input),
                        const SizedBox(height: 700),
                        FilledButton(
                          onPressed: () => completed = true,
                          child: const Text('Save notes'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Open notes'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open notes'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Save notes'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        tester.getBottomLeft(find.text('Save notes')).dy,
        lessThanOrEqualTo(500),
      );
      await tester.tap(find.text('Save notes'));
      expect(completed, isTrue);
      expect(input.text, 'Keep this draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('padded popup forms keep their last control above the home '
      'indicator', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEpTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEpSheet(
                context,
                (context) => EpFormSheet(
                  title: 'Confirm',
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Confirm'),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester.getBottomLeft(find.byType(FilledButton)).dy,
      lessThanOrEqualTo(844 - 34 - 24),
    );
  });
}
