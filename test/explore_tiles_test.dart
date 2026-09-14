import 'package:earplug/app_state.dart';
import 'package:earplug/explore_ranking.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
import 'package:earplug/widgets/ep_rows.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/explore_friends.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/fan_event_card.dart';
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
          72 + 6 + 2 + line(textTheme.epLabel) * 3 + line(textTheme.epMeta) * 2;
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

  testWidgets('venue rail height fits the tallest tile at any text scale', (
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
      expect(
        tester.getSize(tile).height,
        lessThanOrEqualTo(exploreVenueRailHeight(context)),
      );
    }
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

  testWidgets('event row shows metadata, generated flyer, and taps', (
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
    expect(
      find.descendant(
        of: find.byType(ExploreEventRow),
        matching: find.byType(GigFlyer),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ExploreEventRow),
        matching: find.text('NN'),
      ),
      findsNothing,
    );
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

  testWidgets('cancelled event row shows the CANCELLED marker', (tester) async {
    final gig = gigFixture(
      id: 'cancelled-row',
      title: 'Cancelled Show',
      lifecycle: GigLifecycle.cancelled,
    );
    await tester.pumpWidget(
      plain(ExploreEventRow(gig: gig, venueName: 'The Foghorn', onTap: () {})),
    );
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.byKey(ValueKey('gig-cancelled-${gig.id}')), findsOneWidget);
  });

  testWidgets('event row stretches actions and centers plain trailing icons', (
    tester,
  ) async {
    final gig = gigFixture(id: 'trailing-row', title: 'Neon Nights');
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          sub: 'Live music at The Foghorn',
          stretchTrailing: true,
          trailing: const Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.bookmark_border, key: Key('row-trailing-top')),
              Icon(Icons.circle, key: Key('row-trailing-bottom')),
            ],
          ),
          onTap: () {},
        ),
      ),
    );

    final thumbnail = find.descendant(
      of: find.byType(ExploreEventRow),
      matching: find.byType(EpNetworkImage),
    );
    expect(
      tester.getRect(find.byKey(const Key('row-trailing-top'))).top,
      closeTo(tester.getRect(thumbnail).top, 1),
    );
    expect(
      tester.getRect(find.byKey(const Key('row-trailing-bottom'))).bottom,
      closeTo(tester.getRect(thumbnail).bottom, 1),
    );

    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          sub: 'Live music at The Foghorn',
          trailing: const Icon(Icons.chevron_right, key: Key('row-chevron')),
          onTap: () {},
        ),
      ),
    );
    expect(
      tester.getRect(find.byKey(const Key('row-chevron'))).center.dy,
      closeTo(tester.getRect(find.byType(ExploreEventRow)).center.dy, 1),
    );
  });

  testWidgets('event row shows known friends and hides them by default', (
    tester,
  ) async {
    final gig = gigFixture(id: 'friends-row');
    final friends = [
      const SocialUserCard(userId: 'a', name: 'Maya'),
      const SocialUserCard(userId: 'b', name: 'Dev'),
    ];
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          friends: friends,
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(ExploreAvatarStack), findsOneWidget);
    expect(find.text('Maya and Dev are going'), findsOneWidget);

    await tester.pumpWidget(
      plain(ExploreEventRow(gig: gig, venueName: 'The Foghorn', onTap: () {})),
    );
    expect(find.byType(ExploreAvatarStack), findsNothing);
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

  testWidgets('event row places actions at the row top-right', (tester) async {
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gigFixture(id: 'poster-actions'),
          venueName: 'The Foghorn',
          actions: const [Icon(Icons.bookmark, key: Key('poster-save'))],
          onTap: () {},
        ),
      ),
    );
    final row = tester.getRect(find.byType(ExploreEventRow));
    final action = tester.getRect(find.byKey(const Key('poster-save')));
    final poster = tester.getRect(
      find.descendant(
        of: find.byType(ExploreEventRow),
        matching: find.byType(EpNetworkImage),
      ),
    );
    expect(action.top, closeTo(poster.top, 1));
    expect(action.right, lessThanOrEqualTo(row.right));
    expect(action.left, greaterThan(row.center.dx));
    expect(action.left, greaterThan(poster.right));

    await tester.pumpWidget(
      plain(
        SizedBox(
          width: 300,
          child: ExploreEventRow(
            gig: gigFixture(
              id: 'narrow-actions',
              title: 'A Very Long Event Title That Must Leave Room For Actions',
            ),
            venueName: 'The Foghorn',
            actions: const [
              Icon(Icons.bookmark, key: Key('narrow-save')),
              Icon(Icons.ios_share, key: Key('narrow-share')),
            ],
            onTap: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('event row omits the fallback chevron when actions are present', (
    tester,
  ) async {
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gigFixture(id: 'actions-no-chevron', title: 'Action Event'),
          venueName: 'The Foghorn',
          actions: const [Icon(Icons.bookmark)],
          onTap: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('event row wraps long titles beside actions', (tester) async {
    const title =
        'A Very Long Event Title That Must Wrap Within A Narrow Card Width';
    await tester.pumpWidget(
      plain(
        SizedBox(
          width: 300,
          child: ExploreEventRow(
            gig: gigFixture(id: 'long-title-actions', title: title),
            venueName: 'The Foghorn',
            info: const ExploreGigInfo(
              dateTime: '23 SEP · 8PM',
              distance: '2.3 MI',
              price: '\$15',
            ),
            lineup: const [
              ExploreLineupBand(name: 'Aster', initials: 'AS'),
              ExploreLineupBand(name: 'Briar', initials: 'BR'),
              ExploreLineupBand(name: 'Cinder', initials: 'CI'),
            ],
            actions: const [Icon(Icons.bookmark), Icon(Icons.ios_share)],
            onTap: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final titleText = tester.widget<Text>(find.text(title.toUpperCase()));
    expect(
      tester.getSize(find.text(title.toUpperCase())).height,
      greaterThan(24),
    );
    expect(titleText.softWrap, isTrue);
  });

  testWidgets('event row info wraps and emphasizes date and time', (
    tester,
  ) async {
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gigFixture(id: 'structured-info'),
          venueName: 'The Foghorn',
          info: const ExploreGigInfo(
            dateTime: '23 SEP · 8PM',
            distance: 'A VERY LONG DISTANCE LABEL',
            price: 'A VERY LONG PRICE LABEL',
          ),
          onTap: () {},
        ),
      ),
    );
    final infoText = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
      ),
    );
    expect(infoText.softWrap, isTrue);
    expect(infoText.overflow, isNot(TextOverflow.ellipsis));
    final firstSpan =
        (infoText.textSpan! as TextSpan).children!.first as TextSpan;
    expect(firstSpan.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('lineup row shows all chips when wide and see all when narrow', (
    tester,
  ) async {
    const bands = [
      ExploreLineupBand(name: 'Aster', initials: 'AS'),
      ExploreLineupBand(name: 'Briar', initials: 'BR'),
      ExploreLineupBand(name: 'Cinder', initials: 'CI'),
    ];
    await tester.pumpWidget(
      plain(SizedBox(width: 700, child: ExploreLineupRow(bands: bands))),
    );
    expect(find.text('Aster'), findsOneWidget);
    expect(find.text('Briar'), findsOneWidget);
    expect(find.text('Cinder'), findsOneWidget);
    expect(find.byKey(const Key('lineup-see-all')), findsNothing);

    var tapped = false;
    await tester.pumpWidget(
      plain(
        SizedBox(
          width: 300,
          child: ExploreLineupRow(
            bands: const [
              ExploreLineupBand(name: 'A Very Long Band Name', initials: 'AL'),
              ExploreLineupBand(name: 'Another Long Band Name', initials: 'AN'),
              ExploreLineupBand(name: 'Third Long Band Name', initials: 'TL'),
            ],
            onSeeAll: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('lineup-see-all')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lineup-see-all')));
    expect(tapped, isTrue);
  });

  testWidgets(
    'lineup row always shows the first band even when it must ellipsize',
    (tester) async {
      const bands = [
        ExploreLineupBand(name: 'A Very Long Band Name Indeed', initials: 'AV'),
        ExploreLineupBand(name: 'Second', initials: 'SE'),
      ];
      await tester.pumpWidget(
        plain(SizedBox(width: 200, child: ExploreLineupRow(bands: bands))),
      );
      expect(find.byType(EpAvatarTile), findsOneWidget);
      expect(find.byKey(const Key('lineup-see-all')), findsOneWidget);

      await tester.pumpWidget(
        plain(SizedBox(width: 700, child: ExploreLineupRow(bands: bands))),
      );
      expect(find.text('A Very Long Band Name Indeed'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(find.byKey(const Key('lineup-see-all')), findsNothing);
    },
  );

  testWidgets('lineup is pinned to the poster bottom edge', (tester) async {
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gigFixture(id: 'lineup-bottom'),
          venueName: 'The Foghorn',
          lineup: const [ExploreLineupBand(name: 'Aster', initials: 'AS')],
          onTap: () {},
        ),
      ),
    );
    final poster = tester.getRect(find.byType(EpNetworkImage));
    final lineup = tester.getRect(find.byType(ExploreLineupRow));
    expect(lineup.bottom, closeTo(poster.bottom, 1));
  });

  testWidgets('compact and featured cards have no ticket pills', (
    tester,
  ) async {
    await pumpApp(
      tester,
      home: Scaffold(
        body: Consumer<AppState>(
          builder: (context, app, _) => FanEventCard(
            gig: gigFixture(id: 'compact-no-ticket'),
            app: app,
          ),
        ),
      ),
    );
    expect(find.byType(EpPill), findsNothing);
    await tester.pumpWidget(
      plain(
        ExploreFeaturedCard(
          gig: gigFixture(id: 'featured-no-ticket'),
          venueName: 'The Foghorn',
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(EpPill), findsNothing);
  });

  testWidgets('featured card renders meta and lineup chips', (tester) async {
    final gig = gigFixture(id: 'featured-lineup', title: 'Featured Event');
    await tester.pumpWidget(
      plain(
        ExploreFeaturedCard(
          gig: gig,
          venueName: 'The Foghorn',
          meta: '23 Sep · 8PM · FREE · 11 MI',
          lineup: const [
            ExploreLineupBand(name: 'Aster', initials: 'AS'),
            ExploreLineupBand(name: 'Briar', initials: 'BR'),
            ExploreLineupBand(name: 'Cinder', initials: 'CI'),
            ExploreLineupBand(name: 'Fourth', initials: 'FO'),
          ],
          onTap: () {},
          width: 334,
          height: 200,
        ),
      ),
    );

    expect(find.textContaining('23 SEP · 8PM · FREE · 11 MI'), findsOneWidget);
    expect(find.text('Aster'), findsOneWidget);
    expect(find.text('Briar'), findsNothing);
    expect(find.text('Cinder'), findsNothing);
    expect(find.byKey(const Key('lineup-see-all')), findsOneWidget);
  });

  testWidgets('featured card uses generated flyer without duplicating title', (
    tester,
  ) async {
    final gig = gigFixture(
      id: 'featured-generated-flyer',
      title: 'Generated Flyer Event',
      flyerUrl: null,
    );
    await tester.pumpWidget(
      plain(
        ExploreFeaturedCard(gig: gig, venueName: 'The Foghorn', onTap: () {}),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(ExploreFeaturedCard),
        matching: find.byType(GigFlyer),
      ),
      findsOneWidget,
    );
    expect(find.text('GENERATED FLYER EVENT'), findsOneWidget);
  });

  testWidgets('featured card shows details and taps', (tester) async {
    var tapped = false;
    for (final tix in Ticketing.values) {
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
      expect(find.text('RSVP'), findsNothing);
      expect(find.text('TICKETS'), findsNothing);
      expect(find.text('GOING'), findsNothing);
      await tester.tap(find.text('A LONG FEATURED EVENT TITLE'));
    }
    expect(tapped, isTrue);
  });

  testWidgets('featured card shows known friends and hides them by default', (
    tester,
  ) async {
    final gig = gigFixture(id: 'friends-featured');
    final friends = [const SocialUserCard(userId: 'a', name: 'Maya')];
    await tester.pumpWidget(
      plain(
        ExploreFeaturedCard(
          gig: gig,
          venueName: 'The Foghorn',
          friends: friends,
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(ExploreAvatarStack), findsOneWidget);
    expect(find.text('MAYA GOING'), findsOneWidget);

    await tester.pumpWidget(
      plain(
        ExploreFeaturedCard(gig: gig, venueName: 'The Foghorn', onTap: () {}),
      ),
    );
    expect(find.byType(ExploreAvatarStack), findsNothing);
    expect(find.text('MAYA GOING'), findsNothing);
  });

  testWidgets(
    'landscape featured card fits its title, meta and lineup at 1.0 and 1.5',
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
              meta: '23 Sep · 8PM · FREE · 11 MI',
              lineup: const [
                ExploreLineupBand(name: 'Aster', initials: 'AS'),
                ExploreLineupBand(name: 'Briar', initials: 'BR'),
                ExploreLineupBand(name: 'Cinder', initials: 'CI'),
              ],
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
          find.textContaining('23 SEP · 8PM · FREE · 11 MI'),
          findsOneWidget,
        );
        expect(find.text('TICKETS'), findsNothing);
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
      expect(find.text('19 SEP'), findsOneWidget);
      expect(find.text('1 SHOW'), findsOneWidget);
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
      expect(find.text('19 SEP'), findsOneWidget);
      expect(find.text('2 SHOWS'), findsOneWidget);
      expect(find.text('VERIFIED'), findsNothing);
    },
  );

  testWidgets('venue tile uses photos and a no-photo placeholder', (
    tester,
  ) async {
    final date = DateTime(2026, 9, 19);
    final photoVenue = Venue(
      id: 'venue-photo',
      name: 'Photo Room',
      area: 'Oakland',
      addr: '1 Main St',
      point: const LatLng(0, 0),
      photoUrls: const ['https://example.com/venue.jpg'],
    );
    await tester.pumpWidget(
      plain(
        ExploreVenueTile(
          entry: VenueWithShows(
            venue: photoVenue,
            gigs: [gigFixture(id: 'photo-show', startsAt: date)],
          ),
          onTap: () {},
        ),
      ),
    );
    final photoImage = find.byType(EpNetworkImage);
    expect(photoImage, findsOneWidget);
    expect(
      tester.widget<EpNetworkImage>(photoImage).url,
      'https://example.com/venue.jpg',
    );

    final emptyVenue = Venue(
      id: 'venue-no-photo',
      name: 'Empty Room',
      area: 'Oakland',
      addr: '2 Main St',
      point: const LatLng(0, 0),
    );
    await tester.pumpWidget(
      plain(
        ExploreVenueTile(
          entry: VenueWithShows(
            venue: emptyVenue,
            gigs: [gigFixture(id: 'empty-show', startsAt: date)],
          ),
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(EpNetworkImage), findsNothing);
    expect(find.text('NO PHOTO YET'), findsOneWidget);
  });

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
        friends: const [SocialUserCard(userId: 'a', name: 'Maya')],
        onTap: () {},
      ),
      ExploreFeaturedCard(
        gig: gig,
        venueName: 'A Venue With A Long Name',
        friends: const [SocialUserCard(userId: 'a', name: 'Maya')],
        onTap: () {},
      ),
      ExploreLocationRow(label: 'A Location With A Long Name', onTap: () {}),
    ]) {
      debugPrint('scale child: ${child.runtimeType}');
      await tester.pumpWidget(plain(child, textScaler: scaler));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
