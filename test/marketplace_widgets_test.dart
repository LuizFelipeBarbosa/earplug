import 'package:earplug/models.dart';
import 'package:earplug/money.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/approx_area_map.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:earplug/widgets/map_view.dart';
import 'package:earplug/widgets/money_text.dart';
import 'package:earplug/widgets/status_timeline.dart';
import 'package:earplug/widgets/venue_location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/harness.dart';

void main() {
  testWidgets('status timeline renders and identifies every step state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const StatusTimeline(
          steps: [
            TimelineStep(label: 'Submitted', state: TimelineStepState.done),
            TimelineStep(
              label: 'In review',
              caption: 'The venue is checking the offer.',
              state: TimelineStepState.current,
            ),
            TimelineStep(label: 'Confirmed', state: TimelineStepState.pending),
            TimelineStep(label: 'Payout', state: TimelineStepState.blocked),
          ],
        ),
      ),
    );

    for (var index = 0; index < 4; index++) {
      expect(find.byKey(Key('timeline-step-$index')), findsOneWidget);
    }
    expect(find.bySemanticsLabel('In review, current'), findsOneWidget);
    expect(find.bySemanticsLabel('Confirmed, pending'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('money text formats positive, negative, and signed amounts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyText(Money(125000)),
            MoneyText(Money(-500)),
            MoneyText(Money(500), signed: true),
          ],
        ),
      ),
    );

    expect(find.text(r'$1,250.00'), findsOneWidget);
    expect(find.text(r'-$5.00'), findsOneWidget);
    expect(find.text(r'+$5.00'), findsOneWidget);
  });

  test('money JSON defaults missing values to zero US dollars', () {
    expect(Money.fromJson(null), Money.zero);
    expect(Money.fromJson(const {}), Money.zero);
  });

  testWidgets('venue editor emits field edits and requires a pin', (
    tester,
  ) async {
    var draft = const VenueLocationDraft();
    final harness = await pumpApp(
      tester,
      home: Scaffold(
        body: SingleChildScrollView(
          child: VenueLocationEditor(
            initial: draft,
            keyPrefix: 'marketplace-venue',
            onChanged: (value) => draft = value,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('marketplace-venue-name')),
      'Harbor Loft',
    );
    await tester.enterText(
      find.byKey(const Key('marketplace-venue-address')),
      '9 Pier Street',
    );
    await tester.enterText(
      find.byKey(const Key('marketplace-venue-area')),
      'Oakland',
    );
    await tester.pump();

    expect(draft.name, 'Harbor Loft');
    expect(draft.address, '9 Pier Street');
    expect(draft.area, 'Oakland');
    expect(draft.isComplete, isFalse);

    final map = tester.widget<EpMap>(
      find.descendant(
        of: find.byKey(const Key('marketplace-venue-map')),
        matching: find.byType(EpMap),
      ),
    );
    map.options.onTap!(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(37.8, -122.27),
    );
    await tester.pump();

    expect(draft.pin, const LatLng(37.8, -122.27));
    expect(draft.isComplete, isTrue);
    harness.app.dispose();
  });

  testWidgets('approximate area map renders a ring without a pin', (
    tester,
  ) async {
    final harness = await pumpApp(
      tester,
      home: const Scaffold(
        body: ApproxAreaMap(centroid: LatLng(37.7749, -122.4194)),
      ),
    );

    expect(find.byType(ApproxAreaMap), findsOneWidget);
    expect(find.byType(CircleLayer), findsOneWidget);
    expect(find.byType(MarkerLayer), findsNothing);
    expect(find.byIcon(Icons.location_pin), findsNothing);
    harness.app.dispose();
  });

  testWidgets('venue mini-map supports an approximate area', (tester) async {
    final harness = await pumpApp(
      tester,
      home: Scaffold(
        body: VenueMiniMap(
          approximate: true,
          venue: Venue(
            id: 'venue-1',
            name: 'Harbor Loft',
            area: 'Oakland',
            addr: '9 Pier Street',
            point: LatLng(37.8, -122.27),
          ),
        ),
      ),
    );

    expect(find.byType(VenueMiniMap), findsOneWidget);
    expect(find.byType(CircleLayer), findsOneWidget);
    expect(find.byType(MarkerLayer), findsNothing);
    harness.app.dispose();
  });
}

Widget _host(Widget child) => MaterialApp(
  theme: buildEpTheme(),
  home: Scaffold(body: Center(child: child)),
);
