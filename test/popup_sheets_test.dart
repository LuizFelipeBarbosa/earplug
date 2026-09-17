import 'package:earplug/widgets/ep_sheet.dart';
import 'package:earplug/widgets/sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

void main() {
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
        epApp(
          Builder(
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
      epApp(
        Builder(
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
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester.getBottomLeft(find.byType(FilledButton)).dy,
      lessThanOrEqualTo(844 - 34 - 20),
    );
  });
}
