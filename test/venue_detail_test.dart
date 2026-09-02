import 'package:earplug/screens/venue_detail.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  testWidgets('venue hero and directory use only supported venue facts', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: const Scaffold(body: VenueDetailScreen(venueId: 'v1')),
    );

    expect(find.byKey(const Key('venue-detail-hero')), findsOne);
    expect(find.text('THE FOGHORN CLUB'), findsOne);
    expect(find.textContaining('2455 Harrison St'), findsOne);
    expect(find.byKey(const Key('venue-detail-distance')), findsOne);
    expect(find.byType(VenueMiniMap), findsOne);
    expect(find.textContaining('DOOR POLICY'), findsNothing);
    expect(find.textContaining('PAST EVENTS'), findsNothing);

    final visibleCards = tester.widgetList<FanEventCard>(
      find.byType(FanEventCard),
    );
    expect(visibleCards, isNotEmpty);
    expect(
      visibleCards.every(
        (card) => card.presentation == FanEventCardPresentation.compact,
      ),
      isTrue,
    );
  });
}
