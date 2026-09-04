import 'dart:async';

import 'package:earplug/services/geocoding_service.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:earplug/widgets/venue_location_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  testWidgets('fewer than three address characters do not start a search', (
    tester,
  ) async {
    final geocoding = FakeGeocodingService();
    final harness = await pumpApp(
      tester,
      geocoding: geocoding,
      home: _EditorHost(geocoding: geocoding),
    );

    await tester.enterText(find.byKey(const Key('venue-test-address')), 'Va');
    await tester.pump(const Duration(milliseconds: 400));

    expect(geocoding.queries, isEmpty);
    expect(find.byKey(const Key('venue-test-area')), findsNothing);
    harness.app.dispose();
  });

  testWidgets('address input is debounced into one search', (tester) async {
    final geocoding = FakeGeocodingService();
    final harness = await pumpApp(
      tester,
      geocoding: geocoding,
      home: _EditorHost(geocoding: geocoding),
    );

    final address = find.byKey(const Key('venue-test-address'));
    await tester.enterText(address, 'Val');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(address, 'Valencia');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(geocoding.queries, ['Valencia']);
    harness.app.dispose();
  });

  testWidgets('picking a suggestion fills the draft and moves the map', (
    tester,
  ) async {
    final geocoding = FakeGeocodingService();
    VenueLocationDraft draft = const VenueLocationDraft();
    final harness = await pumpApp(
      tester,
      geocoding: geocoding,
      home: _EditorHost(
        geocoding: geocoding,
        onChanged: (value) => draft = value,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('venue-test-address')),
      'Valencia',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byKey(const Key('venue-test-suggestion-0')));
    await tester.pumpAndSettle();

    final picked = geocoding.suggestions.first;
    expect(draft.address, picked.address);
    expect(draft.area, picked.area);
    expect(draft.pin, picked.point);
    expect(draft.isComplete, isTrue);
    expect(find.text('Fans will see: Mission'), findsOneWidget);

    final map = tester.widget<EpMap>(
      find.descendant(
        of: find.byKey(const Key('venue-test-map')),
        matching: find.byType(EpMap),
      ),
    );
    final center = map.mapController!.camera.center;
    expect(center.latitude, closeTo(picked.point.latitude, 0.0005));
    expect(center.longitude, closeTo(picked.point.longitude, 0.0005));
    expect(map.mapController!.camera.zoom, 16);
    harness.app.dispose();
  });

  testWidgets('a stale response cannot replace newer suggestions', (
    tester,
  ) async {
    final firstGate = Completer<List<AddressSuggestion>>();
    final secondGate = Completer<List<AddressSuggestion>>();
    final geocoding = FakeGeocodingService()..gate = firstGate;
    final harness = await pumpApp(
      tester,
      geocoding: geocoding,
      home: _EditorHost(geocoding: geocoding),
    );

    final address = find.byKey(const Key('venue-test-address'));
    await tester.enterText(address, 'First query');
    await tester.pump(const Duration(milliseconds: 300));
    expect(geocoding.queries, ['First query']);

    geocoding.gate = secondGate;
    await tester.enterText(address, 'Second query');
    await tester.pump(const Duration(milliseconds: 300));
    expect(geocoding.queries, ['First query', 'Second query']);

    const newer = AddressSuggestion(
      label: 'Newer result',
      address: '200 Newer St',
      area: 'Oakland',
      point: LatLng(37.8, -122.27),
    );
    const older = AddressSuggestion(
      label: 'Older result',
      address: '100 Older St',
      area: 'Mission',
      point: LatLng(37.76, -122.42),
    );
    secondGate.complete([newer]);
    await tester.pump();
    firstGate.complete([older]);
    await tester.pump();

    expect(find.text('Newer result'), findsOneWidget);
    expect(find.text('Older result'), findsNothing);
    harness.app.dispose();
  });

  testWidgets('unauthorized search falls back to tap-to-place', (tester) async {
    final geocoding = FakeGeocodingService()
      ..failure = const GeocodingUnauthorized();
    VenueLocationDraft draft = const VenueLocationDraft();
    final harness = await pumpApp(
      tester,
      geocoding: geocoding,
      home: _EditorHost(
        geocoding: geocoding,
        onChanged: (value) => draft = value,
      ),
    );

    await tester.enterText(
      find.byKey(const Key('venue-test-address')),
      'Valencia',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      find.byKey(const Key('venue-test-search-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('venue-test-suggestions')), findsNothing);

    final map = tester.widget<EpMap>(
      find.descendant(
        of: find.byKey(const Key('venue-test-map')),
        matching: find.byType(EpMap),
      ),
    );
    map.options.onTap!(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(37.76, -122.42),
    );
    await tester.pump();

    expect(draft.pin, const LatLng(37.76, -122.42));
    harness.app.dispose();
  });

  testWidgets('disabled editor blocks fields and map changes', (tester) async {
    const initial = VenueLocationDraft(address: '22 Valencia St');
    var draft = initial;
    final geocoding = FakeGeocodingService();
    final harness = await pumpApp(
      tester,
      geocoding: geocoding,
      home: _EditorHost(
        geocoding: geocoding,
        enabled: false,
        showNameField: true,
        initial: initial,
        onChanged: (value) => draft = value,
      ),
    );

    final nameField = tester.widget<TextField>(
      find.byKey(const Key('venue-test-name')),
    );
    final addressField = tester.widget<TextField>(
      find.byKey(const Key('venue-test-address')),
    );
    expect(nameField.enabled, isFalse);
    expect(addressField.enabled, isFalse);

    final map = tester.widget<EpMap>(
      find.descendant(
        of: find.byKey(const Key('venue-test-map')),
        matching: find.byType(EpMap),
      ),
    );
    map.options.onTap!(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(37.76, -122.42),
    );
    await tester.pump();

    expect(draft, same(initial));
    expect(geocoding.queries, isEmpty);
    harness.app.dispose();
  });
}

class _EditorHost extends StatelessWidget {
  const _EditorHost({
    required this.geocoding,
    this.onChanged,
    this.initial = const VenueLocationDraft(),
    this.enabled = true,
    this.showNameField = false,
  });

  final FakeGeocodingService geocoding;
  final ValueChanged<VenueLocationDraft>? onChanged;
  final VenueLocationDraft initial;
  final bool enabled;
  final bool showNameField;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: VenueLocationEditor(
          initial: initial,
          keyPrefix: 'venue-test',
          showNameField: showNameField,
          enabled: enabled,
          geocoding: geocoding,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    );
  }
}
