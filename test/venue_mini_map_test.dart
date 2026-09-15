import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/venue_mini_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const venue = Venue(
    id: 'venue-map-test',
    name: 'The Foghorn',
    area: 'Mission',
    addr: '1 Main St',
    point: LatLng(37.76, -122.41),
  );

  Widget plain(Widget child, {Brightness brightness = Brightness.dark}) =>
      MaterialApp(
        theme: buildEpTheme(brightness),
        home: Scaffold(body: child),
      );

  testWidgets('renders one map and one marker at the venue point', (
    tester,
  ) async {
    await tester.pumpWidget(plain(const VenueMapPreview(venue: venue)));
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter, venue.point);
    expect(map.options.initialZoom, 15);
    expect(map.options.interactionOptions.flags, InteractiveFlag.none);
    expect(find.byType(MarkerLayer), findsOneWidget);
    final markers = tester
        .widget<MarkerLayer>(find.byType(MarkerLayer))
        .markers;
    expect(markers, hasLength(1));
    expect(markers.single.point, venue.point);
    expect(tester.getSize(find.byType(VenueMapPreview)).height, 160);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the show-count overlay in light and dark themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        plain(
          const VenueMapPreview(venue: venue, overlayLabel: '3 SHOWS'),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();

      final overlay = find.byKey(const Key('venue-map-overlay'));
      expect(overlay, findsOneWidget);
      expect(
        find.descendant(of: overlay, matching: find.text('3 SHOWS')),
        findsOneWidget,
      );
      final colors = tester.element(overlay).epColors;
      expect(tester.widget<Container>(overlay).color, colors.background);
      final label = tester.widget<Text>(find.text('3 SHOWS'));
      expect(label.style!.color, colors.ink);
      expect(label.maxLines, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('omits the overlay when the label is omitted or empty', (
    tester,
  ) async {
    for (final preview in [
      const VenueMapPreview(venue: venue),
      const VenueMapPreview(venue: venue, overlayLabel: ''),
    ]) {
      await tester.pumpWidget(plain(preview));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('venue-map-overlay')), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
