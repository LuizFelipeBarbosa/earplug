import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/screens/analytics.dart';
import 'package:earplug/screens/analytics_sheets.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/recap_fixtures.dart';

void main() {
  testWidgets('show section actions open the complete shows sheet', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: ManyShowsRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );

    await _tapSectionButton(tester, 'analytics-turnout-see-all');

    final sheet = find.byKey(const Key('analytics-shows-sheet'));
    expect(sheet, findsOne);
    for (var number = 1; number <= 12; number++) {
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(
            'Show ${number.toString().padLeft(2, '0')}',
            skipOffstage: false,
          ),
        ),
        findsOne,
      );
    }
    expect(
      find.descendant(
        of: sheet,
        matching: find.textContaining('AVG ', skipOffstage: false),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(AnalyticsStackedBar)),
      findsNWidgets(12),
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await _tapSectionButton(tester, 'analytics-new-returning-see-all');
    expect(find.byKey(const Key('analytics-shows-sheet')), findsOne);
  });

  testWidgets('new and returning action includes shows without a split', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _PartialSplitRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('analytics-new-returning-see-all')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final card = find.byKey(const Key('analytics-new-returning'));
    expect(
      find.descendant(of: card, matching: find.byType(AnalyticsStackedBar)),
      findsNWidgets(4),
    );
    expect(
      find.descendant(of: card, matching: find.text('SEE ALL 12')),
      findsOne,
    );

    await tester.tap(find.byKey(const Key('analytics-new-returning-see-all')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('analytics-shows-sheet'));
    final showRows = find.descendant(
      of: sheet,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            (widget.properties.label ?? '').contains(' measured RSVPs'),
        skipOffstage: false,
      ),
    );
    expect(showRows, findsNWidgets(12));
    expect(
      find.descendant(of: sheet, matching: find.byType(AnalyticsStackedBar)),
      findsNWidgets(4),
    );
  });

  testWidgets('rooms action opens every venue with show and RSVP context', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: ManyShowsRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );

    await _tapSectionButton(tester, 'analytics-rooms-see-all');

    final sheet = find.byKey(const Key('analytics-rows-sheet'));
    expect(sheet, findsOne);
    for (var number = 1; number <= 8; number++) {
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(
            'Venue ${number.toString().padLeft(2, '0')}',
            skipOffstage: false,
          ),
        ),
        findsOne,
      );
    }
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('3 shows · 240 total RSVPs', skipOffstage: false),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Venue 08, 80 avg, 3 shows · 240 total RSVPs',
          skipOffstage: false,
        ),
      ),
      findsOne,
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await _tapSectionButton(tester, 'analytics-best-nights-see-all');
    expect(find.text('ALL 7 NIGHTS'), findsOne);
  });

  testWidgets('forty-show recap remains overflow-free at narrow large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: FortyShowsRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );
    tester.view.physicalSize = const Size(320, 1800);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await _tapSectionButton(tester, 'analytics-turnout-see-all');
    expect(find.byKey(const Key('analytics-shows-sheet')), findsOne);
    expect(tester.takeException(), isNull);
  });

  test('recapVsAverageLabel describes relative turnout', () {
    expect(recapVsAverageLabel(30, 20), '+50% vs avg');
    expect(recapVsAverageLabel(10, 20), '-50% vs avg');
    expect(recapVsAverageLabel(20, 20), 'at avg');
    expect(recapVsAverageLabel(0, 0), 'at avg');
    expect(recapVsAverageLabel(3, 0), 'above avg');
  });
}

Future<void> _tapSectionButton(WidgetTester tester, String key) async {
  final button = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    button,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _PartialSplitRecapRepository extends DemoRepository {
  _PartialSplitRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async =>
      manyShowsRecapWithPartialSplit(12, splitCount: 4);
}
