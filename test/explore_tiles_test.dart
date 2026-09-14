import 'package:earplug/app_state.dart';
import 'package:earplug/explore_ranking.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

void main() {
  Widget plain(Widget child, {TextScaler? textScaler}) => MaterialApp(
    theme: buildEpTheme(),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        textScaler: textScaler ?? TextScaler.noScaling,
      ),
      child: Scaffold(body: child),
    ),
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
    expect(find.text('garage · surf punk'), findsOneWidget);
    await tester.tap(find.text('The Tile Band'));
    expect(tapped, isTrue);
  });

  testWidgets('collection card shows title, show count, and handles taps', (
    tester,
  ) async {
    var tapped = false;
    final collection = ExploreCollection(
      key: 'week',
      kind: ExploreCollectionKind.week,
      title: 'Weekend picks',
      gigs: [
        gigFixture(id: 'g1'),
        gigFixture(id: 'g2'),
      ],
      score: 1,
    );
    await tester.pumpWidget(
      plain(
        ExploreCollectionCard(
          collection: collection,
          onTap: () => tapped = true,
        ),
      ),
    );

    expect(find.text('WEEKEND PICKS'), findsOneWidget);
    expect(find.text('2 SHOWS'), findsOneWidget);
    await tester.tap(find.text('WEEKEND PICKS'));
    expect(tapped, isTrue);
  });

  testWidgets('event row shows metadata, fallback initials, and taps', (
    tester,
  ) async {
    var tapped = false;
    final gig = gigFixture(
      id: 'event-row',
      title: 'Neon Nights',
      startsAt: DateTime(2026, 9, 19),
      flyKey: 'paper',
      price: 0,
    );
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          onTap: () => tapped = true,
        ),
      ),
    );
    expect(find.text('NEON NIGHTS'), findsOneWidget);
    expect(find.text('NN'), findsOneWidget);
    expect(find.textContaining('19 SEP'), findsOneWidget);
    expect(find.textContaining('The Foghorn'), findsOneWidget);
    await tester.tap(find.text('NEON NIGHTS'));
    expect(tapped, isTrue);

    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gigFixture(id: 'paid-row', title: 'Paid Night', price: 12),
          venueName: 'The Foghorn',
          onTap: () {},
        ),
      ),
    );
    expect(find.textContaining('FREE'), findsNothing);
  });

  testWidgets('event row supports custom metadata and thumbnail size', (
    tester,
  ) async {
    const meta = 'WED 23 SEP · 8PM · FREE · 11.2 mi';
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gigFixture(id: 'custom-meta-row'),
          venueName: 'The Foghorn',
          meta: meta,
          thumbnailSize: 72.5,
          onTap: () {},
        ),
      ),
    );

    final metaText = tester.widget<Text>(
      find.text('WED 23 SEP · 8PM · FREE · 11.2 MI'),
    );
    expect(metaText.semanticsLabel, meta);
    expect(metaText.maxLines, 1);
    expect(find.textContaining('The Foghorn'), findsNothing);
    final thumbnail = find.descendant(
      of: find.byType(ExploreEventRow),
      matching: find.byType(EpNetworkImage),
    );
    final thumbnailSize = tester.getSize(thumbnail);
    final rowHeight = tester.getSize(find.byType(ExploreEventRow)).height;
    expect(thumbnailSize.width, 72.5);
    expect(thumbnailSize.height, closeTo(rowHeight - 25, 0.1));
    final image = tester.widget<EpNetworkImage>(thumbnail);
    expect(image.cacheWidth, 73);
    expect(image.cacheHeight, isNull);
  });

  testWidgets('event imagery uses flyer photos for every fly key', (
    tester,
  ) async {
    const flyerUrl = 'https://example.com/flyer.jpg';
    final gig = gigFixture(
      id: 'photo-row',
      title: 'Photo Event',
      flyKey: 'paper',
      flyerUrl: flyerUrl,
    );
    await tester.pumpWidget(
      plain(
        Column(
          children: [
            ExploreEventRow(gig: gig, venueName: 'The Foghorn', onTap: () {}),
            ExploreFeaturedCard(
              gig: gig,
              venueName: 'The Foghorn',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    final images = tester.widgetList<EpNetworkImage>(
      find.byType(EpNetworkImage),
    );
    expect(images, hasLength(2));
    expect(images.every((image) => image.url == flyerUrl), isTrue);
  });

  testWidgets('event row renders lineup avatars and names', (tester) async {
    final gig = gigFixture(id: 'lineup-row', title: 'Lineup Event');
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          lineup: const [
            ExploreLineupBand(name: 'Mission Creep', initials: 'MC'),
            ExploreLineupBand(name: 'Static Bloom', initials: 'SB'),
          ],
          onTap: () {},
        ),
      ),
    );

    expect(find.text('Mission Creep'), findsOneWidget);
    expect(find.text('Static Bloom'), findsOneWidget);
    final missionCreep = tester.getTopLeft(find.text('Mission Creep'));
    final staticBloom = tester.getTopLeft(find.text('Static Bloom'));
    expect(staticBloom.dy, closeTo(missionCreep.dy, 0.5));
    expect(staticBloom.dx, greaterThan(missionCreep.dx + 40));
    expect(
      find.descendant(
        of: find.byType(ExploreEventRow),
        matching: find.byType(EpAvatarTile),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('featured card shows details, ticket cue, and taps', (
    tester,
  ) async {
    var tapped = false;
    for (final tix in Ticketing.values) {
      final cue = switch (tix) {
        Ticketing.rsvp => 'RSVP',
        Ticketing.paid => 'TICKETS',
        Ticketing.external => 'DETAILS',
      };
      await tester.pumpWidget(
        plain(
          ExploreFeaturedCard(
            gig: gigFixture(
              id: 'featured-${tix.name}',
              title: 'A Long Featured Event Title',
              time: '8PM / 9PM',
              tix: tix,
            ),
            venueName: 'The Foghorn',
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.text('A LONG FEATURED EVENT TITLE'), findsOneWidget);
      expect(find.textContaining('THE FOGHORN · DOORS 8PM'), findsOneWidget);
      expect(find.text(cue), findsOneWidget);
      await tester.tap(find.text('A LONG FEATURED EVENT TITLE'));
    }
    expect(tapped, isTrue);
  });

  testWidgets(
    'landscape featured card fits its title, venue line and cue at 1.0 and 1.5',
    (tester) async {
      final gig = gigFixture(
        id: 'featured-landscape',
        title: 'A Very Long Featured Event Title That Needs Trimming',
        time: '8PM / 9PM',
        tix: Ticketing.paid,
      );
      for (final scale in [1.0, 1.5]) {
        await tester.pumpWidget(
          plain(
            ExploreFeaturedCard(
              gig: gig,
              venueName: 'A Venue With A Long Name',
              onTap: () {},
              width: 334,
              height: 200,
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scale $scale');
        expect(
          tester.getSize(find.byType(ExploreFeaturedCard)),
          const Size(334, 200),
        );
        expect(
          find.text('A VERY LONG FEATURED EVENT TITLE THAT NEEDS TRIMMING'),
          findsOneWidget,
        );
        expect(
          find.textContaining('A VENUE WITH A LONG NAME · DOORS 8PM'),
          findsOneWidget,
        );
        expect(find.text('TICKETS'), findsOneWidget);
      }
    },
  );

  testWidgets('location row shows copy and handles taps', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      plain(ExploreLocationRow(label: 'Oakland', onTap: () => tapped = true)),
    );
    expect(find.text('OAKLAND'), findsOneWidget);
    expect(find.text('Set as your location'), findsOneWidget);
    await tester.tap(find.text('OAKLAND'));
    expect(tapped, isTrue);
  });

  testWidgets(
    'venue tile renders metadata, singular/plural, and verification',
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
      expect(find.text('SAT 19 · 1 SHOW'), findsOneWidget);
      expect(find.text('VERIFIED'), findsOneWidget);

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
      expect(find.text('SAT 19 · 2 SHOWS'), findsOneWidget);
      expect(find.text('VERIFIED'), findsNothing);
    },
  );

  testWidgets('band row preserves follow pill and directory copy', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: Scaffold(
        body: Consumer<AppState>(
          builder: (context, app, _) => ExploreBandRow(bandId: 'b1', app: app),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('explore-band-card-b1')), findsOneWidget);
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
    final collection = ExploreCollection(
      key: 'large',
      kind: ExploreCollectionKind.week,
      title: 'A Collection Title That Needs Several Lines',
      gigs: [gigFixture(id: 'large-gig')],
      score: 0,
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
      ExploreCollectionCard(collection: collection, onTap: () {}),
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
        onTap: () {},
      ),
      ExploreFeaturedCard(
        gig: gig,
        venueName: 'A Venue With A Long Name',
        onTap: () {},
      ),
      ExploreLocationRow(label: 'A Location With A Long Name', onTap: () {}),
    ]) {
      await tester.pumpWidget(plain(child, textScaler: scaler));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
