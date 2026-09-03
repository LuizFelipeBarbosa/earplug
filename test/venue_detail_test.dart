import 'package:earplug/screens/gig_create.dart';
import 'package:earplug/screens/gig_detail.dart';
import 'package:earplug/screens/venue_detail.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('approximate verified venue keeps its exact location private', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
    );

    expect(find.byKey(const Key('venue-detail-approx-note')), findsOne);
    expect(
      tester
          .widget<VenueMiniMap>(find.byKey(const Key('venue-detail-map')))
          .approximate,
      isTrue,
    );
    expect(find.byKey(const Key('venue-detail-verified')), findsOne);
    expect(find.textContaining('2455 Harrison St'), findsNothing);
  });

  testWidgets('exact unverified venue shows its public address', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v2')),
    );

    expect(find.text('486 40th St, Oakland'), findsOne);
    expect(find.byKey(const Key('venue-detail-approx-note')), findsNothing);
    expect(find.byKey(const Key('venue-detail-verified')), findsNothing);
  });

  testWidgets('approximate venue gig does not offer directions', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g2')),
    );

    expect(find.byKey(const Key('gig-venue-directions')), findsNothing);
  });

  testWidgets('exact venue gig offers directions', (tester) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: GigDetailScreen(gigId: 'g3')),
    );

    expect(find.byKey(const Key('gig-venue-directions')), findsOne);
  });

  testWidgets('gig venue picker does not offer venue creation', (tester) async {
    await pumpApp(
      tester,
      beforePump: (app) async {
        await tester.pumpAndSettle();
        app.startGigCreate();
      },
      home: const Scaffold(body: GigCreateScreen()),
    );

    await tester.tap(find.text('Choose a venue'));
    await tester.pumpAndSettle();

    expect(find.text('+ NEW VENUE'), findsNothing);
  });
}
