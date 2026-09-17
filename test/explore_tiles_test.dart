import 'package:earplug/app_state.dart';
import 'package:earplug/explore_ranking.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_map.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';
import 'support/pump.dart';

void main() {
  group('explore tiles', () {
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

    testWidgets('band tile shows fallback, genres, and handles taps', (
      tester,
    ) async {
      var tapped = false;
      final band = bandFixture(
        id: 'tile-band',
        name: 'The Tile Band',
        initials: 'TB',
        genres: ['garage', 'surf punk', 'noise'],
      );
      await tester.pumpWidget(
        plain(ExploreBandTile(band: band, onTap: () => tapped = true)),
      );

      expect(find.text('TB'), findsOneWidget);
      expect(find.text('The Tile Band'), findsOneWidget);
      expect(find.text('garage · surf punk · noise'), findsOneWidget);
      final genreText = tester.widget<Text>(
        find.text('garage · surf punk · noise'),
      );
      expect(genreText.maxLines, 2);
      expect(genreText.softWrap, isTrue);
      final nameText = tester.widget<Text>(find.text('The Tile Band'));
      expect(nameText.maxLines, 3);
      expect(nameText.softWrap, isTrue);
      // Content is left-aligned so the first avatar in a rail sits on the
      // gutter, under the section heading.
      final tileLeft = tester.getTopLeft(find.byType(ExploreBandTile)).dx;
      expect(tester.getTopLeft(find.byType(EpAvatarTile)).dx, tileLeft);
      expect(tester.getTopLeft(find.text('The Tile Band')).dx, tileLeft);
      expect(nameText.textAlign, TextAlign.left);
      expect(genreText.textAlign, TextAlign.left);
      await tester.tap(find.text('The Tile Band'));
      expect(tapped, isTrue);

      await tester.pumpWidget(
        plain(
          ExploreBandTile(
            band: bandFixture(
              id: 'long-tile-band',
              name:
                  'The Very Long Band Name That Should Wrap Across Several Lines',
              genres: ['garage'],
            ),
            onTap: () {},
          ),
        ),
      );
      expect(
        tester
            .widget<Text>(
              find.text(
                'The Very Long Band Name That Should Wrap Across Several Lines',
              ),
            )
            .maxLines,
        3,
      );
    });

    testWidgets('compact band tile centres the avatar over the name', (
      tester,
    ) async {
      for (final name in [
        'Rex',
        'The Very Long Band Name That Cannot Fit In Eighty-Eight Pixels',
      ]) {
        var tapped = false;
        await tester.pumpWidget(
          plain(
            Row(
              children: [
                ExploreBandTile.compact(
                  band: bandFixture(id: 'compact-band', name: name),
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: name);
        final tileRect = tester.getRect(find.byType(ExploreBandTile));
        final avatarRect = tester.getRect(find.byType(EpAvatarTile));
        final nameRect = tester.getRect(find.text(name));
        expect(tileRect.width, 88, reason: name);
        expect(avatarRect.width, 56, reason: name);
        expect(
          avatarRect.center.dx,
          closeTo(nameRect.center.dx, 1),
          reason: name,
        );
        expect(
          avatarRect.center.dx,
          closeTo(tileRect.center.dx, 1),
          reason: name,
        );
        expect(nameRect.width, lessThanOrEqualTo(tileRect.width), reason: name);
        final nameText = tester.widget<Text>(find.text(name));
        expect(nameText.maxLines, 1);
        expect(nameText.overflow, TextOverflow.ellipsis);
        expect(nameText.textAlign, TextAlign.center);
        // The tap target spans the full tile width, not just the avatar.
        await tester.tapAt(Offset(tileRect.left + 2, avatarRect.center.dy));
        expect(tapped, isTrue, reason: name);
      }
    });

    testWidgets('band rail height fits the tallest tile at any text scale', (
      tester,
    ) async {
      final band = bandFixture(
        id: 'tall-band',
        name: 'The Very Long Band Name That Should Wrap Across Several Lines',
        genres: ['garage', 'surf punk', 'noise', 'post-hardcore', 'shoegaze'],
      );
      for (final scale in [1.0, 1.3]) {
        // A Column gives the tile unbounded height, so it takes its content
        // height instead of filling the screen.
        await tester.pumpWidget(
          plain(
            Column(
              children: [ExploreBandTile(band: band, onTap: () {})],
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        final tile = find.byType(ExploreBandTile);
        final context = tester.element(tile);
        final textTheme = Theme.of(context).textTheme;
        double line(TextStyle style) =>
            (style.fontSize! * style.height! * scale).ceilToDouble();
        final expected =
            72 +
            6 +
            2 +
            line(textTheme.epLabel) * 3 +
            line(textTheme.epMeta) * 2;
        final rail = exploreBandRailHeight(context);
        expect(rail, expected);
        // Name and genres both hit their line caps in this fixture, so the
        // tile is as tall as it ever gets; the rail must contain it with no
        // more than the per-line rounding slack to spare.
        expect(tester.widget<Text>(find.text(band.name)).maxLines, 3);
        final tileHeight = tester.getSize(tile).height;
        expect(tileHeight, lessThanOrEqualTo(rail));
        expect(tileHeight, greaterThan(rail - 5));
      }
    });

    testWidgets('venue rail height matches the tile at any text scale', (
      tester,
    ) async {
      final venue = Venue(
        id: 'tall-venue',
        name: 'The Very Long Venue Name That Wraps Across Two Lines',
        area: 'Mission',
        addr: '1 Main St',
        point: const LatLng(0, 0),
        verified: true,
      );
      final entry = VenueWithShows(
        venue: venue,
        gigs: [gigFixture(id: 'tall-venue-show', venueId: venue.id)],
      );
      for (final scale in [1.0, 1.3]) {
        await tester.pumpWidget(
          plain(
            Column(
              children: [
                ExploreVenueTile(entry: entry, distance: '12 MI', onTap: () {}),
              ],
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'scale $scale');
        final tile = find.byType(ExploreVenueTile);
        final context = tester.element(tile);
        final tileRect = tester.getRect(tile);
        final mapRect = tester.getRect(find.byKey(const Key('venue-tile-map')));
        final nameRect = tester.getRect(find.text(venue.name.toUpperCase()));
        final areaRect = tester.getRect(find.text(venue.area));
        expect(mapRect.width, tileRect.width);
        expect(mapRect.height, tileRect.width / 2);
        expect(nameRect.left, mapRect.left);
        expect(areaRect.left, mapRect.left);
        expect(nameRect.top - mapRect.bottom, 14);
        final overlayRect = tester.getRect(
          find.byKey(const Key('venue-map-overlay')),
        );
        expect(overlayRect.left, mapRect.left + 8);
        expect(overlayRect.bottom, mapRect.bottom - 8);
        expect(overlayRect.top, greaterThanOrEqualTo(mapRect.top));
        expect(overlayRect.right, lessThanOrEqualTo(mapRect.right));
        expect(tileRect.height, closeTo(exploreVenueRailHeight(context), 0.01));
      }
    });

    testWidgets(
      'venue tile renders metadata and singular/plural without verification badges',
      (tester) async {
        final date = DateTime(2026, 9, 19); // Saturday.
        final venue = Venue(
          id: 'venue-verified',
          name: 'The Foghorn',
          area: 'Mission',
          addr: '1 Main St',
          point: const LatLng(0, 0),
          neighborhood: 'The Mission',
          verified: true,
        );
        final entry = VenueWithShows(
          venue: venue,
          gigs: [gigFixture(id: 'single', venueId: venue.id, startsAt: date)],
        );
        await tester.pumpWidget(
          plain(ExploreVenueTile(entry: entry, distance: '2 MI', onTap: () {})),
        );
        expect(find.text('THE FOGHORN'), findsOneWidget);
        expect(find.text('The Mission'), findsOneWidget);
        expect(find.text('19 SEP'), findsNothing);
        expect(find.textContaining('SEP'), findsNothing);
        expect(find.text('1 SHOW'), findsOneWidget);
        expect(find.byKey(const Key('venue-tile-map')), findsOneWidget);
        final map = tester.widget<EpMap>(
          find.descendant(
            of: find.byKey(const Key('venue-tile-map')),
            matching: find.byType(EpMap),
          ),
        );
        expect(map.showAttribution, isFalse);
        expect(find.byKey(const Key('venue-map-overlay')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('venue-map-overlay')),
            matching: find.text('1 SHOW'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(ExploreVenueTile),
            matching: find.byType(EpBadge),
          ),
          findsNothing,
        );

        final unverified = Venue(
          id: 'venue-plain',
          name: 'Plain Room',
          area: 'Oakland',
          addr: '2 Main St',
          point: const LatLng(0, 0),
        );
        await tester.pumpWidget(
          plain(
            ExploreVenueTile(
              entry: VenueWithShows(
                venue: unverified,
                gigs: [
                  gigFixture(id: 'a', venueId: unverified.id, startsAt: date),
                  gigFixture(
                    id: 'b',
                    venueId: unverified.id,
                    startsAt: date.add(const Duration(days: 1)),
                  ),
                ],
              ),
              onTap: () {},
            ),
          ),
        );
        expect(find.text('19 SEP'), findsNothing);
        expect(find.textContaining('SEP'), findsNothing);
        expect(find.text('2 SHOWS'), findsOneWidget);
        expect(find.byKey(const Key('venue-tile-map')), findsOneWidget);
        expect(find.byKey(const Key('venue-map-overlay')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('venue-map-overlay')),
            matching: find.text('2 SHOWS'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(ExploreVenueTile),
            matching: find.byType(EpBadge),
          ),
          findsNothing,
        );

        for (final name in ['', '   ']) {
          final unnamed = Venue(
            id: 'venue-unnamed',
            name: name,
            area: 'Sunset',
            addr: '99 Ocean Ave',
            point: const LatLng(0, 0),
          );
          await tester.pumpWidget(
            plain(
              ExploreVenueTile(
                entry: VenueWithShows(
                  venue: unnamed,
                  gigs: [gigFixture(id: 'unnamed-show', venueId: unnamed.id)],
                ),
                onTap: () {},
              ),
            ),
          );
          expect(find.text('99 OCEAN AVE'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) => widget is Text && widget.data?.trim().isEmpty == true,
            ),
            findsNothing,
          );
          final tileSemantics = tester.widget<Semantics>(
            find.descendant(
              of: find.byType(ExploreVenueTile),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics && widget.properties.button == true,
              ),
            ),
          );
          expect(tileSemantics.properties.label, unnamed.addr);
        }
      },
    );

    testWidgets(
      'venue tiles align name and area line tops across different content',
      (tester) async {
        final shortVenue = Venue(
          id: 'short-venue',
          name: 'Short',
          area: 'Mission',
          addr: '1 Main St',
          point: const LatLng(0, 0),
          verified: true,
        );
        final longVenue = Venue(
          id: 'long-venue',
          name: 'A Very Long Venue Name That Wraps Across Two Lines',
          area: 'Oakland',
          addr: '2 Main St',
          point: const LatLng(0, 0),
        );
        for (final scale in [1.0, 1.3]) {
          await tester.pumpWidget(
            plain(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExploreVenueTile(
                    entry: VenueWithShows(
                      venue: shortVenue,
                      gigs: [
                        gigFixture(id: 'short-show', venueId: shortVenue.id),
                      ],
                    ),
                    distance: '2 MI',
                    onTap: () {},
                  ),
                  ExploreVenueTile(
                    entry: VenueWithShows(
                      venue: longVenue,
                      gigs: [
                        gigFixture(id: 'long-show-a', venueId: longVenue.id),
                        gigFixture(id: 'long-show-b', venueId: longVenue.id),
                      ],
                    ),
                    distance: null,
                    onTap: () {},
                  ),
                ],
              ),
              textScaler: TextScaler.linear(scale),
            ),
          );
          expect(tester.takeException(), isNull, reason: 'scale $scale');
          expect(find.text('2 MI'), findsOneWidget);
          final shortName = find.text(shortVenue.name.toUpperCase());
          final longName = find.text(longVenue.name.toUpperCase());
          // Confirm that the fixtures exercise different numbers of name lines.
          expect(
            tester.getSize(longName).height,
            greaterThan(tester.getSize(shortName).height),
          );
          for (final (shortText, longText) in [
            (shortName, longName),
            (find.text(shortVenue.area), find.text(longVenue.area)),
          ]) {
            expect(
              (tester.getTopLeft(shortText).dy - tester.getTopLeft(longText).dy)
                  .abs(),
              lessThan(0.5),
              reason: 'scale $scale: $shortText and $longText',
            );
          }
        }
      },
    );

    testWidgets('band row preserves follow pill and directory copy', (
      tester,
    ) async {
      await pumpApp(
        tester,
        home: Scaffold(
          body: Consumer<AppState>(
            builder: (context, app, _) =>
                ExploreBandRow(bandId: 'b1', app: app),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('explore-band-card-b1')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('explore-follow-b1')), findsOneWidget);
      expect(find.text('FOLLOW'), findsOneWidget);
      expect(find.textContaining('fans'), findsOneWidget);
    });

    testWidgets('band page status renders loading, error, load-more, and end', (
      tester,
    ) async {
      await pumpApp(
        tester,
        beforePump: (app) => app.exploreBandsLoading = true,
        home: Consumer<AppState>(
          builder: (context, app, _) => ExploreBandPageStatus(app: app),
        ),
      );
      expect(find.byKey(const Key('explore-bands-loading')), findsOneWidget);

      await pumpApp(
        tester,
        beforePump: (app) => app.exploreBandsError = 'network',
        home: Consumer<AppState>(
          builder: (context, app, _) => ExploreBandPageStatus(app: app),
        ),
      );
      expect(find.byKey(const Key('explore-bands-retry')), findsOneWidget);

      await pumpApp(
        tester,
        home: Consumer<AppState>(
          builder: (context, app, _) => ExploreBandPageStatus(app: app),
        ),
      );
      expect(find.byKey(const Key('explore-bands-load-more')), findsOneWidget);

      await pumpApp(
        tester,
        beforePump: (app) async {
          app.ensureExploreBands();
        },
        home: Consumer<AppState>(
          builder: (context, app, _) => ExploreBandPageStatus(app: app),
        ),
      );
      expect(find.byKey(const Key('explore-bands-end')), findsOneWidget);
    });

    testWidgets('tiles are safe at larger text scale', (tester) async {
      final band = bandFixture(
        id: 'large-band',
        name: 'A Very Long Band Name That Wraps',
        genres: ['garage', 'surf punk'],
      );
      final venue = Venue(
        id: 'large-venue',
        name: 'A Venue With A Long Name',
        area: 'Oakland',
        addr: '1 Main',
        point: const LatLng(0, 0),
        verified: true,
      );
      final scaler = TextScaler.linear(1.5);
      final gig = gigFixture(
        id: 'large-event',
        title: 'A Very Long Event Recommendation Title',
      );
      for (final child in [
        ExploreBandTile(band: band, onTap: () {}),
        ExploreVenueTile(
          entry: VenueWithShows(
            venue: venue,
            gigs: [gigFixture(id: 'large-show', venueId: venue.id)],
          ),
          distance: '12 MI',
          onTap: () {},
        ),
        ExploreEventRow(
          gig: gig,
          venueName: 'A Venue With A Long Name',
          lines: GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: gig.title,
            location: 'Southside · 11.2 mi',
            price: gig.priceLabel,
          ),
          onTap: () {},
        ),
        ExploreFeaturedCard(
          gig: gig,
          venueName: 'A Venue With A Long Name',
          lines: GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: gig.title,
            location: 'Southside · 11.2 mi',
            price: gig.priceLabel,
          ),
          onTap: () {},
        ),
      ]) {
        debugPrint('scale child: ${child.runtimeType}');
        await tester.pumpWidget(plain(child, textScaler: scaler));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
