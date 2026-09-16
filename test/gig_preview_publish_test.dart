import 'package:earplug/app_state.dart';
import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  testWidgets('preview publish is disabled with a missing venue', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    app.setGfName('Some Gig');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.previewGigDraft();
    await tester.pumpAndSettle();

    final publish = find.byKey(const Key('gig-preview-publish'));
    expect(tester.widget<EpPill>(publish).onPressed, isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('gig-publish-hint')),
        matching: find.textContaining('STILL NEEDS A VENUE'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('preview publish is enabled and publishes a complete draft', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    app.setGfName('Some Gig');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');
    app.previewGigDraft();
    await tester.pumpAndSettle();

    final publish = find.byKey(const Key('gig-preview-publish'));
    expect(tester.widget<EpPill>(publish).onPressed, isNotNull);
    expect(find.byKey(const Key('gig-publish-hint')), findsNothing);

    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    await tester.tap(publish);
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is EpDisplay && widget.text == "It's live.",
      ),
      findsOneWidget,
    );
    expect(find.text("IT'S LIVE."), findsOneWidget);
  });

  testWidgets('preview publish scrolls inline after the venue card', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    app.setGfName('Some Gig');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');
    app.previewGigDraft();
    await tester.pumpAndSettle();

    final venue = find.byKey(const Key('gig-venue-card'));
    final publish = find.byKey(const Key('gig-preview-publish'));

    await tester.ensureVisible(venue);
    await tester.pumpAndSettle();
    final scrollable = Scrollable.of(tester.element(venue));
    // Compare content coordinates so the widgets need not be visible together.
    final venueBottom =
        tester.getBottomLeft(venue).dy + scrollable.position.pixels;

    await tester.ensureVisible(publish);
    await tester.pumpAndSettle();
    expect(Scrollable.of(tester.element(publish)), same(scrollable));
    final publishTop =
        tester.getTopLeft(publish).dy + scrollable.position.pixels;
    expect(venueBottom, lessThanOrEqualTo(publishTop));

    final offset = scrollable.position.pixels;
    expect(offset, greaterThan(0));
    final topBeforeScroll = tester.getTopLeft(publish).dy;
    scrollable.position.jumpTo(offset / 2);
    await tester.pump();
    expect(
      tester.getTopLeft(publish).dy - topBeforeScroll,
      closeTo(offset / 2, 0.01),
    );
  });

  testWidgets('null footer leaves the fan presentation without publish UI', (
    tester,
  ) async {
    final gig = gigFixture(id: 'fan-gig', title: 'Fan gig');
    await pumpApp(
      tester,
      beforePump: (_) async {
        await tester.pumpAndSettle();
      },
      home: Scaffold(
        body: Builder(
          builder: (context) => GigDetailPresentation(
            gig: gig,
            app: context.watch<AppState>(),
            performers: const [],
            footer: null,
          ),
        ),
      ),
    );

    expect(find.byType(GigDetailPresentation), findsOneWidget);
    expect(find.byKey(const Key('gig-preview-publish')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<AppHarness> _pumpGigCreate(WidgetTester tester) => pumpApp(
  tester,
  beforePump: (app) async {
    await tester.pumpAndSettle();
    app.startGigCreate();
  },
  home: const Scaffold(body: GigCreateScreen()),
);
