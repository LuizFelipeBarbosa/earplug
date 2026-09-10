import 'package:earplug/data/demo_repository.dart';
import 'package:earplug/data/repository.dart';
import 'package:earplug/models.dart';
import 'package:earplug/screens/analytics.dart';
import 'package:earplug/screens/analytics_sheets.dart';
import 'package:earplug/services/auth_service.dart';
import 'package:earplug/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';
import 'support/stub_repository.dart';

void main() {
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

  testWidgets('average divider aligns with a show at the window average', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('bandRecap', _averageMatchingRecap),
      home: const Scaffold(body: AnalyticsScreen()),
    );

    await tester.scrollUntilVisible(
      find.text('CHECK-INS BY SHOW'),
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

  testWidgets('empty state renders without populated cards', (tester) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: StubRepository(auth: auth)
        ..returns('bandRecap', BandRecap.empty),
      home: const Scaffold(body: AnalyticsScreen()),
    );

    expect(find.textContaining('No past gigs yet for'), findsOne);
    expect(find.text('CHECK-INS BY SHOW'), findsNothing);
  });

  testWidgets(
    'tied zero-turnout recap chooses newest without dividing by zero',
    (tester) async {
      final auth = FakeAuthService();
      await pumpApp(
        tester,
        auth: auth,
        repository: StubRepository(auth: auth)
          ..returns('bandRecap', _tieZeroRecap),
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

  testWidgets('demo recap does not render see-all actions', (tester) async {
    await pumpApp(tester, home: const Scaffold(body: AnalyticsScreen()));
    tester.view.physicalSize = const Size(402, 5000);
    await tester.pumpAndSettle();

    expect(find.textContaining('SEE ALL'), findsNothing);
  });

  test('forty-show fixture represents the backend recap limit', () async {
    final repository = _FortyShowsRecapRepository(auth: FakeAuthService());

    expect((await repository.bandRecap('band')).shows, hasLength(40));
  });

  testWidgets('show section actions open the complete shows sheet', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpApp(
      tester,
      auth: auth,
      repository: _ManyShowsRecapRepository(auth: auth),
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
      repository: StubRepository(auth: auth)
        ..returns(
          'bandRecap',
          _manyShowsRecapWithPartialSplit(12, splitCount: 4),
        ),
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

    await tester.ensureVisible(
      find.byKey(const Key('analytics-new-returning-see-all')),
    );
    await tester.pumpAndSettle();
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
      repository: _ManyShowsRecapRepository(auth: auth),
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
      repository: _FortyShowsRecapRepository(auth: auth),
      home: const Scaffold(body: AnalyticsScreen()),
    );
    tester.view.physicalSize = const Size(320, 1800);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('analytics-best-show')), findsOne);
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
  // Insights can finish loading during the scroll and shift later sections.
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

const _tieZeroRecap = BandRecap(
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

const _averageMatchingRecap = BandRecap(
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

class _ManyShowsRecapRepository extends DemoRepository {
  _ManyShowsRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => _manyShowsRecap(12);
}

class _FortyShowsRecapRepository extends DemoRepository {
  _FortyShowsRecapRepository({required super.auth});

  @override
  Future<BandRecap> bandRecap(String bandId) async => _manyShowsRecap(40);
}

BandRecap _manyShowsRecap(int showCount) =>
    _manyShowsRecapImpl(showCount, splitCount: showCount);

BandRecap _manyShowsRecapWithPartialSplit(
  int showCount, {
  required int splitCount,
}) {
  assert(splitCount >= 0 && splitCount <= showCount);
  return _manyShowsRecapImpl(showCount, splitCount: splitCount);
}

BandRecap _manyShowsRecapImpl(int showCount, {required int splitCount}) {
  final firstShow = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch;
  final shows = [
    for (var index = 0; index < showCount; index++)
      RecapShow(
        gigId: 'show-${index + 1}',
        title: 'Show ${(index + 1).toString().padLeft(2, '0')}',
        startsAt: firstShow + index * const Duration(days: 1).inMilliseconds,
        venueName: 'Venue ${(index % 8 + 1).toString().padLeft(2, '0')}',
        price: 0,
        ticketing: Ticketing.rsvp,
        goingCount: 10 + index,
        measuredRsvps: 10 + index,
        newFans: index < splitCount ? 6 + index : null,
        returningFans: index < splitCount ? 4 : null,
      ),
  ];
  final measuredRsvps = shows.fold<int>(
    0,
    (total, show) => total + show.measuredRsvps,
  );

  return BandRecap(
    window: RecapWindow(
      showsAnalyzed: showCount,
      scanned: showCount,
      truncated: false,
      firstStartsAt: shows.first.startsAt,
      lastStartsAt: shows.last.startsAt,
    ),
    totals: RecapTotals(
      shows: showCount,
      reportedRsvps: measuredRsvps,
      measuredRsvps: measuredRsvps,
      avgPerShow: measuredRsvps / showCount,
      bestShowRsvps: shows.last.measuredRsvps,
      distinctFans: measuredRsvps,
      followerCount: measuredRsvps,
    ),
    shows: shows,
    newReturningSuppressed: false,
    leadTime: const RecapLeadTime(
      buckets: [
        RecapBucket(key: 'twoWeeksPlus', count: 12),
        RecapBucket(key: 'oneToTwoWeeks', count: 18),
        RecapBucket(key: 'underWeek', count: 24),
        RecapBucket(key: 'dayOf', count: 9),
      ],
      medianDays: 6,
      unmeasurable: 0,
      suppressed: false,
    ),
    venues: RecapVenues(
      rows: [
        for (var number = 1; number <= 8; number++)
          RecapVenue(
            venueName: 'Venue ${number.toString().padLeft(2, '0')}',
            shows: number % 3 + 1,
            totalRsvps: number * 10 * (number % 3 + 1),
            avgRsvps: number * 10,
          ),
      ],
      suppressed: false,
    ),
    weekdays: RecapWeekdays(
      rows: [
        for (var weekday = 1; weekday <= 7; weekday++)
          RecapWeekday(weekday: weekday, shows: 2, avgRsvps: weekday * 5),
      ],
      suppressed: false,
    ),
    repeatFans: const RecapRepeatFans(
      tiers: [
        RecapBucket(key: 'one', count: 30),
        RecapBucket(key: 'twoToThree', count: 18),
        RecapBucket(key: 'fourPlus', count: 7),
      ],
      suppressed: false,
    ),
    pricing: const RecapPricing(
      freeShows: 12,
      freeAvgRsvps: 15.5,
      paidShows: 0,
      paidAvgRsvps: 0,
      suppressed: false,
    ),
  );
}
