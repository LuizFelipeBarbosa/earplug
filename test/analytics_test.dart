import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/screens/analytics.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('headline stats render', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: AnalyticsScreen()));

    expect(find.text('SHOWS PLAYED'), findsOne);
    expect(find.text('5'), findsOne);
    expect(find.text('TOTAL RSVPS'), findsOne);
    expect(find.text('190'), findsOne);
    expect(find.text('AVG / SHOW'), findsOne);
    expect(find.text('38.0'), findsOne);
  });

  testWidgets('turnout by show renders newest first', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: AnalyticsScreen()));

    await tester.scrollUntilVisible(
      find.text('TURNOUT BY SHOW'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final title = find.text('TURNOUT BY SHOW', skipOffstage: false);
    expect(title, findsOne);

    final card = find.ancestor(
      of: title,
      matching: find.byType(EpCard, skipOffstage: false),
    );
    expect(card, findsOne);

    final expectedTitles = <String>[
      'Summer Static',
      'No Cover Noise',
      'Feedback Friday',
      'Mission Matinee',
      'First Spark',
    ];
    final cardTexts = tester
        .widgetList<Text>(
          find.descendant(
            of: card,
            matching: find.byType(Text, skipOffstage: false),
          ),
        )
        .map((text) => text.data)
        .whereType<String>();
    final renderedTitles = <String>[
      for (final text in cardTexts)
        if (expectedTitles.contains(text)) text,
    ];
    expect(renderedTitles, expectedTitles);
  });

  testWidgets('suppressed section withholds its numbers', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: AnalyticsScreen()));

    await tester.scrollUntilVisible(
      find.text('BEST NIGHTS'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final title = find.text('BEST NIGHTS', skipOffstage: false);
    expect(title, findsOne);

    final card = find.ancestor(
      of: title,
      matching: find.byType(EpCard, skipOffstage: false),
    );
    expect(card, findsOne);
    expect(
      find.descendant(
        of: card,
        matching: find.text('— not enough data yet', skipOffstage: false),
      ),
      findsOne,
    );

    final textWidgets = tester.widgetList<Text>(
      find.descendant(
        of: card,
        matching: find.byType(Text, skipOffstage: false),
      ),
    );
    for (final text in textWidgets) {
      final renderedText = text.data ?? text.textSpan?.toPlainText() ?? '';
      expect(renderedText.contains(RegExp(r'\d')), isFalse);
    }
  });

  testWidgets('published section renders its rows with values', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: AnalyticsScreen()));

    await tester.scrollUntilVisible(
      find.text('ROOMS THAT DRAW'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final title = find.text('ROOMS THAT DRAW', skipOffstage: false);
    expect(title, findsOne);

    final card = find.ancestor(
      of: title,
      matching: find.byType(EpCard, skipOffstage: false),
    );
    expect(card, findsOne);
    const rows = <String, String>{
      'The Knockout': '42.5',
      'Kilowatt': '38',
      'Bottom of the Hill': '33.5',
    };
    for (final row in rows.entries) {
      expect(
        find.descendant(
          of: card,
          matching: find.text(row.key, skipOffstage: false),
        ),
        findsOne,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(row.value, skipOffstage: false),
        ),
        findsOne,
      );
    }
  });

  testWidgets('empty state renders without populated cards', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _EmptyRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );

    expect(
      find.text(
        'No past gigs yet — your recap fills in after your first show.',
      ),
      findsOne,
    );
    expect(find.text('TURNOUT BY SHOW'), findsNothing);
  });
}

class _EmptyRecapRepository extends DemoRepository {
  _EmptyRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => BandRecap.empty;
}
