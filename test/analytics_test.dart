import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
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

  testWidgets('answer board leads with the best-show takeaway', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: AnalyticsScreen()));

    final takeaway = find.byKey(const Key('analytics-best-show'));
    expect(takeaway, findsOne);
    expect(
      find.descendant(
        of: takeaway,
        matching: find.text('BEST SHOW THIS WINDOW'),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: takeaway, matching: find.text('Summer Static')),
      findsOne,
    );
    expect(
      find.descendant(
        of: takeaway,
        matching: find.text('The Knockout · 56 RSVPs · 47% above avg'),
      ),
      findsOne,
    );
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

  testWidgets('average divider aligns with a show at the window average', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _AverageMatchingRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );

    await tester.scrollUntilVisible(
      find.text('TURNOUT BY SHOW'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    final averageShow = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label?.startsWith(
                'Average Show, 20 measured RSVPs',
              ) ==
              true,
    );
    final averageBar = find.descendant(
      of: averageShow,
      matching: find.byType(Container),
    );
    final averageLine = find.byWidgetPredicate(
      (widget) =>
          widget is Row &&
          widget.children.any(
            (child) => child is Expanded && child.child is Divider,
          ),
    );

    expect(averageBar, findsOne);
    expect(find.text('AVG 20'), findsOne);
    expect(averageLine, findsOne);
    expect(
      tester.getTopLeft(averageBar).dy,
      closeTo(tester.getTopLeft(averageLine).dy, 2),
    );
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
        matching: find.text('Not enough data yet', skipOffstage: false),
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

    expect(find.textContaining('No past gigs yet for'), findsOne);
    expect(find.text('TURNOUT BY SHOW'), findsNothing);
  });

  testWidgets(
    'tied zero-turnout recap chooses newest without dividing by zero',
    (tester) async {
      final auth = FakeAuthService();
      await pumpApp(
        tester,
        auth: auth,
        repository: _TieZeroRecapRepository(auth: auth),
        home: const Scaffold(body: AnalyticsScreen()),
      );

      final takeaway = find.byKey(const Key('analytics-best-show'));
      expect(
        find.descendant(
          of: takeaway,
          matching: find.text('BEST SHOW THIS WINDOW · 2-WAY TIE'),
        ),
        findsOne,
      );
      expect(
        find.descendant(of: takeaway, matching: find.text('Newer Zero Show')),
        findsOne,
      );
      expect(
        find.descendant(
          of: takeaway,
          matching: find.text('New Room · 0 RSVPs · at window average'),
        ),
        findsOne,
      );
    },
  );

  testWidgets('all sections and measurement footnotes remain reachable', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _TieZeroRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );
    tester.view.physicalSize = const Size(402, 5000);
    await tester.pumpAndSettle();

    for (final key in [
      'analytics-turnout',
      'analytics-new-returning',
      'analytics-lead-time',
      'analytics-rooms',
      'analytics-best-nights',
      'analytics-repeat-fans',
    ]) {
      expect(find.byKey(Key(key)), findsOne);
    }
    expect(find.textContaining('most recent shows are analyzed'), findsOne);
    expect(find.textContaining('measured RSVP records'), findsOne);
  });

  testWidgets('answer board lays out at narrow width and enlarged text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester, home: const Scaffold(body: AnalyticsScreen()));
    tester.view.physicalSize = const Size(320, 1800);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('analytics-best-show')), findsOne);
    expect(tester.takeException(), isNull);
  });
}

class _EmptyRecapRepository extends DemoRepository {
  _EmptyRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => BandRecap.empty;
}

class _TieZeroRecapRepository extends DemoRepository {
  _TieZeroRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => const BandRecap(
    window: RecapWindow(
      showsAnalyzed: 2,
      scanned: 3,
      truncated: true,
      firstStartsAt: 1000,
      lastStartsAt: 2000,
    ),
    totals: RecapTotals(
      shows: 2,
      reportedRsvps: 2,
      measuredRsvps: 0,
      avgPerShow: 0,
      bestShowRsvps: 0,
      distinctFans: 0,
      followerCount: 0,
    ),
    shows: [
      RecapShow(
        gigId: 'older',
        title: 'Older Zero Show',
        startsAt: 1000,
        venueName: 'Old Room',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 0,
        measuredRsvps: 0,
        newFans: null,
        returningFans: null,
      ),
      RecapShow(
        gigId: 'newer',
        title: 'Newer Zero Show',
        startsAt: 2000,
        venueName: 'New Room',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 0,
        measuredRsvps: 0,
        newFans: null,
        returningFans: null,
      ),
    ],
    newReturningSuppressed: true,
    leadTime: RecapLeadTime(
      buckets: [],
      medianDays: null,
      unmeasurable: 0,
      suppressed: true,
    ),
    venues: RecapVenues(rows: [], suppressed: true),
    weekdays: RecapWeekdays(rows: [], suppressed: true),
    repeatFans: RecapRepeatFans(tiers: [], suppressed: true),
    pricing: RecapPricing(
      freeShows: 0,
      freeAvgRsvps: 0,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: true,
    ),
  );
}

class _AverageMatchingRecapRepository extends DemoRepository {
  _AverageMatchingRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => const BandRecap(
    window: RecapWindow(
      showsAnalyzed: 3,
      scanned: 3,
      truncated: false,
      firstStartsAt: 1000,
      lastStartsAt: 3000,
    ),
    totals: RecapTotals(
      shows: 3,
      reportedRsvps: 60,
      measuredRsvps: 60,
      avgPerShow: 20,
      bestShowRsvps: 30,
      distinctFans: 60,
      followerCount: 60,
    ),
    shows: [
      RecapShow(
        gigId: 'below-average',
        title: 'Below Average Show',
        startsAt: 1000,
        venueName: 'Small Room',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 10,
        measuredRsvps: 10,
        newFans: null,
        returningFans: null,
      ),
      RecapShow(
        gigId: 'at-average',
        title: 'Average Show',
        startsAt: 2000,
        venueName: 'Middle Room',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 20,
        measuredRsvps: 20,
        newFans: null,
        returningFans: null,
      ),
      RecapShow(
        gigId: 'above-average',
        title: 'Above Average Show',
        startsAt: 3000,
        venueName: 'Large Room',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 30,
        measuredRsvps: 30,
        newFans: null,
        returningFans: null,
      ),
    ],
    newReturningSuppressed: true,
    leadTime: RecapLeadTime(
      buckets: [],
      medianDays: null,
      unmeasurable: 0,
      suppressed: true,
    ),
    venues: RecapVenues(rows: [], suppressed: true),
    weekdays: RecapWeekdays(rows: [], suppressed: true),
    repeatFans: RecapRepeatFans(tiers: [], suppressed: true),
    pricing: RecapPricing(
      freeShows: 3,
      freeAvgRsvps: 20,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: true,
    ),
  );
}
