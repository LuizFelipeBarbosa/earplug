import 'package:cached_network_image/cached_network_image.dart';
import 'package:earplug/app_state.dart';
import 'package:earplug/flyer_styles.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/pump.dart';

class _GigLinesApp extends Fake implements AppState {
  _GigLinesApp(this.venueValue, {this.distance = '11.2 mi'});

  final Venue venueValue;
  final String distance;

  @override
  Venue venue(String id) => venueValue;

  @override
  String distanceOf(Venue venue) => distance;
}

void main() {
  group('FanEventCard', () {
    Widget plain(
      Widget child, {
      TextScaler? textScaler,
      Brightness brightness = Brightness.dark,
    }) => epApp(
      child,
      brightness: brightness,
      media: MediaQueryData(
        size: const Size(400, 800),
        textScaler: textScaler ?? TextScaler.noScaling,
      ),
      mediaOutsideScaffold: true,
    );

    test('gig card lines use the start date, doors time, and exact distance', () {
      const venue = Venue(
        id: 'v1',
        name: 'The Foghorn',
        neighborhood: 'Southside',
        area: 'Oakland',
        city: 'San Francisco',
        addr: '1 Main',
        point: LatLng(0, 0),
      );
      final app = _GigLinesApp(venue);
      final gig = gigFixture(
        id: 'card-lines',
        title: 'Neon Nights',
        startsAt: DateTime(2026, 9, 23),
        dateShort: 'TUE JUL 28',
        price: 12,
      );
      final lines = gigCardLines(gig, app, showDistance: true);
      expect(lines.dateLine, 'WED, SEP 23 AT 8PM');
      expect(lines.title, 'Neon Nights');
      expect(lines.location, 'Southside · 11.2 mi');
      expect(lines.price, '\$12');
      expect(gigCardLines(gig, app, showDistance: false).location, 'Southside');
      expect(
        gigCardLines(gigFixture(id: 'free'), app, showDistance: false).price,
        'FREE',
      );
    });

    test(
      'gig card location falls back through area, city, and distance alone',
      () {
        const venue = Venue(
          id: 'v1',
          name: 'The Foghorn',
          area: 'Oakland',
          city: 'San Francisco',
          addr: '1 Main',
          point: LatLng(0, 0),
        );
        final gig = gigFixture(id: 'location-fallbacks');
        for (final entry in [
          (venue: venue, location: 'Oakland'),
          (venue: venue.copyWith(area: ''), location: 'San Francisco'),
          (venue: venue.copyWith(area: '', city: null), location: ''),
        ]) {
          expect(
            gigCardLines(
              gig,
              _GigLinesApp(entry.venue),
              showDistance: false,
            ).location,
            entry.location,
          );
          expect(
            gigCardLines(
              gig,
              _GigLinesApp(entry.venue, distance: ''),
              showDistance: true,
            ).location,
            entry.location,
          );
        }
        expect(
          gigCardLines(
            gig,
            _GigLinesApp(venue.copyWith(area: '', city: null)),
            showDistance: true,
          ).location,
          '11.2 mi',
        );
      },
    );

    testWidgets(
      'snapshot card shows its lines, flyer pattern, and whole-row tap',
      (tester) async {
        var taps = 0;
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            plain(
              FanEventSnapshotCard(
                id: 'snapshot',
                lines: const GigCardLines(
                  dateLine: 'WED, SEP 23 AT 8PM',
                  title: 'Snapshot Night',
                  location: 'The Foghorn',
                  price: '',
                ),
                flyKey: 'riso',
                onTap: () => taps++,
              ),
              brightness: brightness,
            ),
          );
          final card = find.byKey(const ValueKey('fan-event-snapshot-snapshot'));
          expect(card, findsOneWidget);
          for (final label in [
            'WED, SEP 23 AT 8PM',
            'SNAPSHOT NIGHT',
            'The Foghorn',
          ]) {
            expect(
              find.descendant(of: card, matching: find.text(label)),
              findsOneWidget,
            );
          }
          expect(
            tester.widget<FlyerBox>(find.byType(FlyerBox)).style,
            flyerStyles['riso'],
          );
          expect(find.byType(GigFlyer), findsNothing);
          expect(find.byType(CachedNetworkImage), findsNothing);
          expect(find.byType(ExploreCardIconButton), findsNothing);
          expect(
            find.byKey(const ValueKey('snapshot-price-snapshot')),
            findsNothing,
          );
          expect(find.text('FREE'), findsNothing);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith('save-'),
            ),
            findsNothing,
          );
          final thumbnail = find.byType(EpNetworkImage);
          expect(tester.getSize(thumbnail).width, 96);
          expect(tester.widget<EpNetworkImage>(thumbnail).cacheWidth, 96);
          final size = tester.getSize(card);
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
          final location = tester.getRect(find.text('The Foghorn'));
          expect(location.right, closeTo(tester.getRect(card).right, 0.1));
          await tester.tap(thumbnail);
          await tester.tapAt(tester.getRect(card).topRight + const Offset(-2, 2));
          expect(tester.takeException(), isNull);
        }
        expect(taps, 4);
      },
    );

    testWidgets(
      'snapshot card uses a network flyer and an optional plain price',
      (tester) async {
        const flyerUrl = 'https://example.com/snapshot.jpg';
        for (final brightness in Brightness.values) {
          await tester.pumpWidget(
            plain(
              const FanEventSnapshotCard(
                id: 'priced-snapshot',
                rowKey: ValueKey('snapshot-custom-row'),
                lines: GigCardLines(
                  dateLine: 'JAN 2, 2026',
                  title: 'Past Show',
                  location: 'Local venue',
                  price: 'sold out',
                ),
                flyerUrl: flyerUrl,
              ),
              brightness: brightness,
            ),
          );
          final card = find.byKey(const ValueKey('snapshot-custom-row'));
          expect(card, findsOneWidget);
          expect(
            find.byKey(const ValueKey('fan-event-snapshot-priced-snapshot')),
            findsNothing,
          );
          expect(
            tester.widget<EpNetworkImage>(find.byType(EpNetworkImage)).url,
            flyerUrl,
          );
          expect(
            tester
                .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
                .imageUrl,
            flyerUrl,
          );
          final price = tester.widget<Text>(
            find.byKey(const ValueKey('snapshot-price-priced-snapshot')),
          );
          expect(price.data, 'SOLD OUT');
          expect(price.textAlign, TextAlign.right);
          expect(price.style!.fontSize, 13);
          expect(price.style!.color, tester.element(card).epColors.ink);
          expect(find.byType(ExploreCardIconButton), findsNothing);
          expect(
            find.descendant(of: card, matching: find.byType(InkWell)),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'paid and free prices both render as an accent badge',
      (tester) async {
        for (final gig in [
          gigFixture(id: 'paid-price', price: 12),
          gigFixture(id: 'free-price', price: 0),
        ]) {
          await tester.pumpWidget(
            plain(
              ExploreEventRow(
                gig: gig,
                venueName: 'The Foghorn',
                lines: GigCardLines(
                  dateLine: 'WED, SEP 23 AT 8PM',
                  title: gig.title,
                  location: 'Southside',
                  price: gig.priceLabel,
                ),
                onTap: () {},
              ),
            ),
          );

          final price = tester.widget(
            find.byKey(ValueKey('gig-price-${gig.id}')),
          );
          final palette = tester
              .element(find.byKey(ValueKey('gig-price-${gig.id}')))
              .epColors;
          expect(price, isA<Container>());
          expect((price as Container).color, palette.accent);
          expect(price.child, isA<Text>());
          final label = price.child! as Text;
          expect(label.style?.color, palette.onAccent);
        }
      },
    );

    testWidgets('compact fan card trailing action replaces the save action', (
      tester,
    ) async {
      final gig = gigFixture(
        id: 'compact-action-alignment',
        startsAt: DateTime(2026, 9, 23),
      );
      var qrTaps = 0;
      await pumpApp(
        tester,
        home: Scaffold(
          body: Consumer<AppState>(
            builder: (context, app, _) => FanEventCard(
              gig: gig,
              app: app,
              trailingAction: ExploreCardIconButton(
                key: const Key('qr-action'),
                icon: Icons.qr_code,
                semanticLabel: 'Show QR code',
                ring: true,
                onPressed: () => qrTaps++,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(ValueKey('save-${gig.id}')), findsNothing);
      final qr = find.byKey(const Key('qr-action'));
      expect(qr, findsOne);
      expect(tester.widget<ExploreCardIconButton>(qr).ring, isTrue);
      expect(tester.getSize(qr), const Size(36, 36));
      expect(find.byKey(ValueKey('share-${gig.id}')), findsNothing);
      expect(find.byIcon(Icons.ios_share), findsNothing);
      expect(
        tester.getRect(qr).top,
        closeTo(tester.getRect(find.text('WED, SEP 23 AT 8PM')).top, 0.1),
      );
      await tester.tap(qr);
      expect(qrTaps, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
