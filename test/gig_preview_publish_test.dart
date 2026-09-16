import 'package:earplug/app_state.dart';
import 'package:earplug/models.dart';
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

  testWidgets('preview publish stays pinned to the bottom while scrolling', (
    tester,
  ) async {
    final app = (await _pumpGigCreate(tester)).app;
    tester.view.padding = const FakeViewPadding(bottom: 24);
    app.setGfName('Some Gig');
    app.setGfDate(DateTime.now().add(const Duration(days: 2)));
    app.setGfVenue('v1');
    app.previewGigDraft();
    await tester.pumpAndSettle();

    final publish = find.byKey(const Key('gig-preview-publish'));
    final bar = find.byType(EpBottomCta);
    expect(publish, findsOneWidget);
    expect(bar, findsOneWidget);
    expect(find.ancestor(of: publish, matching: bar), findsOneWidget);
    final readyCopy = find.descendant(
      of: bar,
      matching: find.byType(EpMonoText),
    );
    expect(
      tester.widget<EpMonoText>(readyCopy).text,
      'Fans nearby see it as soon as you publish.',
    );
    expect(find.byKey(const Key('gig-buy-tickets')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is EpPill &&
            (widget.label.startsWith('RSVP') ||
                widget.label == 'Going ✓' ||
                widget.label == 'Tickets ↗'),
      ),
      findsNothing,
    );

    // EpBottomCta adds 32px below the pill after applying SafeArea. Read
    // the inset above SafeArea, which removes it from the pill's MediaQuery.
    final mediaQuery = MediaQuery.of(tester.element(bar));
    final expectedBottom =
        mediaQuery.size.height - mediaQuery.padding.bottom - 32;
    expect(tester.getBottomLeft(publish).dy, closeTo(expectedBottom, 0.01));
    expect(tester.getBottomRight(publish).dy, closeTo(expectedBottom, 0.01));
    final publishRect = tester.getRect(publish);

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
    expect(tester.getRect(publish), publishRect);
    expect(publish.hitTestable(), findsOneWidget);
    // Content clears the visible copy as well as the pill; the scrim's
    // transparent top edge can extend above them.
    expect(
      tester.getBottomLeft(find.byKey(const Key('gig-venue-card'))).dy,
      lessThanOrEqualTo(tester.getTopLeft(readyCopy).dy),
    );
  });

  testWidgets('null preview CTA preserves the read-only RSVP stand-in', (
    tester,
  ) async {
    final gig = gigFixture(
      id: 'preview-gig',
      title: 'Preview gig',
      price: 0,
      tix: Ticketing.rsvp,
    );
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
            previewLabel: 'Draft preview',
            previewCta: null,
          ),
        ),
      ),
    );

    expect(find.byType(GigDetailPresentation), findsOneWidget);
    final bar = find.byType(EpBottomCta);
    expect(bar, findsOneWidget);
    expect(tester.widget<EpBottomCta>(bar).hint, 'Free RSVP · preview only');
    expect(
      find.descendant(of: bar, matching: find.text('FREE RSVP · PREVIEW ONLY')),
      findsOneWidget,
    );
    final pill = find.descendant(of: bar, matching: find.byType(EpPill));
    expect(tester.widget<EpPill>(pill).label, 'RSVP');
    expect(tester.widget<EpPill>(pill).onPressed, isNull);
    expect(
      find.descendant(of: pill, matching: find.text('RSVP')),
      findsOneWidget,
    );
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
