import 'package:earplug/app_state.dart';
import 'package:earplug/demo_data.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

void main() {
  testWidgets('compact is the default date-first card presentation', (
    tester,
  ) async {
    final gig = DemoData.gigs.first;
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(gig: gig, app: context.read<AppState>()),
          ),
        ),
      ),
    );

    final card = tester.widget<FanEventCard>(find.byType(FanEventCard));
    expect(card.presentation, FanEventCardPresentation.compact);
    expect(find.byType(DateBlock), findsOne);
    expect(find.byType(GigFlyer), findsNothing);
    expect(find.text('${gig.going} GOING'), findsOne);
    expect(find.byKey(ValueKey('save-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('share-${gig.id}')), findsOne);
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsOne);
  });

  testWidgets('featured presentation uses the resolved presenter and flyer', (
    tester,
  ) async {
    final gig = DemoData.gigs.firstWhere((item) => item.createdByBand != null);
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FanEventCard(
              gig: gig,
              app: context.read<AppState>(),
              presentation: FanEventCardPresentation.featured,
            ),
          ),
        ),
      ),
    );

    final presenter = DemoData.bands[gig.createdByBand]!.name.toUpperCase();
    expect(find.byType(DateBlock), findsNothing);
    expect(find.byType(GigFlyer), findsOne);
    expect(find.text('$presenter PRESENTS'), findsOne);
    expect(find.text(gig.title.toUpperCase()), findsOne);
    expect(find.byKey(ValueKey('ticket-action-${gig.id}')), findsOne);
  });
}
