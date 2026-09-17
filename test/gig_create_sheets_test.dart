import 'package:earplug/app_state.dart';
import 'package:earplug/screens/gig_create_sheets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('when calendar selects and clears a future day at 390px', (
    tester,
  ) async {
    final app = await _pumpWhenSheet(tester);
    expect(find.text('WHEN'), findsOne);
    expect(find.text('CLOSE'), findsOne);
    expect(find.text('DOORS'), findsOne);
    expect(find.text('START'), findsOne);
    expect(find.byType(CupertinoDatePicker), findsNWidgets(2));
    expect(app.gfDate, isNull);

    final now = DateTime.now();
    final date = DateTime(now.year, now.month + 1, 15);
    final day = find.byKey(
      ValueKey('day-${date.year}-${date.month}-${date.day}'),
    );
    final calendar = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(day, 100, scrollable: calendar);
    await tester.pumpAndSettle();
    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(app.gfDate, date);

    await tester.tap(day);
    await tester.pumpAndSettle();
    expect(app.gfDate, isNull);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('DONE'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsNothing);
  });

  testWidgets(
    'both wheels scroll independently even when start precedes doors',
    (tester) async {
      const initialTime = TimeOfDay(hour: 20, minute: 0);
      final app = await _pumpWhenSheet(
        tester,
        seed: (app) {
          app.setGfDoors(initialTime);
          app.setGfStart(initialTime);
        },
      );

      final startWheel = find.byKey(const Key('gig-start-wheel'));
      final startPicker = tester.widget<CupertinoDatePicker>(startWheel);
      final startWheelSize = tester.getSize(startWheel);
      final startHourPoint = tester.getTopLeft(startWheel) +
          Offset(startWheelSize.width * 0.15, startWheelSize.height / 2);
      await tester.dragFrom(
        startHourPoint,
        Offset(0, startPicker.itemExtent),
        touchSlopY: 0,
      );
      await tester.pumpAndSettle();
      expect(app.gfStart, const TimeOfDay(hour: 19, minute: 0));
      expect(app.gfDoors, initialTime);

      final doorsWheel = find.byKey(const Key('gig-doors-wheel'));
      final doorsPicker = tester.widget<CupertinoDatePicker>(doorsWheel);
      final doorsWheelSize = tester.getSize(doorsWheel);
      final doorsHourPoint = tester.getTopLeft(doorsWheel) +
          Offset(doorsWheelSize.width * 0.15, doorsWheelSize.height / 2);
      await tester.dragFrom(
        doorsHourPoint,
        Offset(0, -doorsPicker.itemExtent),
        touchSlopY: 0,
      );
      await tester.pumpAndSettle();
      expect(app.gfDoors, const TimeOfDay(hour: 21, minute: 0));
      expect(app.gfStart, const TimeOfDay(hour: 19, minute: 0));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoDatePicker), findsNothing);
    },
  );

  for (final hasDate in [false, true]) {
    testWidgets(
      'wheel minutes round down using ${hasDate ? 'the selected date' : 'today'}',
      (tester) async {
        final now = DateTime.now();
        final date = hasDate
            ? DateTime(now.year, now.month + 1, 15)
            : DateTime(now.year, now.month, now.day);
        const doors = TimeOfDay(hour: 20, minute: 3);
        const start = TimeOfDay(hour: 21, minute: 59);
        final app = await _pumpWhenSheet(
          tester,
          seed: (app) {
            if (hasDate) app.setGfDate(date);
            app.setGfDoors(doors);
            app.setGfStart(start);
          },
        );

        final doorsPicker = tester.widget<CupertinoDatePicker>(
          find.byKey(const Key('gig-doors-wheel')),
        );
        final startPicker = tester.widget<CupertinoDatePicker>(
          find.byKey(const Key('gig-start-wheel')),
        );
        expect(
          doorsPicker.initialDateTime,
          DateTime(date.year, date.month, date.day, 20),
        );
        expect(
          startPicker.initialDateTime,
          DateTime(date.year, date.month, date.day, 21, 55),
        );
        for (final picker in [doorsPicker, startPicker]) {
          expect(picker.mode, CupertinoDatePickerMode.time);
          expect(picker.minuteInterval, 5);
          expect(picker.use24hFormat, isFalse);
        }
        // Initial wheel rounding does not edit the draft until the user scrolls.
        expect(app.gfDoors, doors);
        expect(app.gfStart, start);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<AppState> _pumpWhenSheet(
  WidgetTester tester, {
  void Function(AppState)? seed,
}) async {
  final harness = await pumpApp(
    tester,
    size: const Size(390, 844),
    beforePump: (app) async {
      await tester.pumpAndSettle();
      app.startGigCreate();
      seed?.call(app);
    },
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showGigWhenSheet(context),
          child: const Text('Open when'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open when'));
  await tester.pumpAndSettle();
  return harness.app;
}
