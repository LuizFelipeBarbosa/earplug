import 'package:earplug/app_state.dart';
import 'package:earplug/explore_ranking.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/common.dart';
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
  Widget plain(
    Widget child, {
    TextScaler? textScaler,
    Brightness brightness = Brightness.dark,
  }) => MaterialApp(
    theme: buildEpTheme(brightness),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(400, 800),
        textScaler: textScaler ?? TextScaler.noScaling,
      ),
      child: Scaffold(body: child),
    ),
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

  testWidgets('card icon button layers the fill beneath the ink outline', (
    tester,
  ) async {
    for (final active in [false, true]) {
      await tester.pumpWidget(
        plain(
          Center(
            child: ExploreCardIconButton(
              icon: Icons.bookmark_border,
              fillIcon: Icons.bookmark,
              semanticLabel: 'Save event',
              active: active,
              onPressed: () {},
            ),
          ),
        ),
      );
      final button = find.byType(ExploreCardIconButton);
      final colors = tester.element(button).epColors;
      final fill = tester.widget<Icon>(find.byIcon(Icons.bookmark));
      final outline = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
      expect(
        fill.color,
        active
            ? colors.accent.withValues(alpha: 0.60)
            : colors.ink.withValues(alpha: 0.22),
      );
      expect(fill.color!.a, closeTo(active ? 0.60 : 0.22, 0.001));
      expect(outline.color, colors.ink);
      expect(outline.color!.a, 1);
      expect(fill.size, 16);
      expect(outline.size, 16);
      expect(tester.getSize(button), const Size(28, 28));
      expect(
        tester.getRect(find.byIcon(Icons.bookmark)),
        tester.getRect(find.byIcon(Icons.bookmark_border)),
      );
      final layers = tester.widget<Stack>(
        find.descendant(of: button, matching: find.byType(Stack)),
      );
      expect((layers.children.first as Icon).icon, Icons.bookmark);
      expect((layers.children.last as Icon).icon, Icons.bookmark_border);
    }
  });

  testWidgets('non-ring action color tints both layers and shadows the glyph', (
    tester,
  ) async {
    final shadows = [
      Shadow(color: Ep.background.withValues(alpha: 0.60), blurRadius: 4),
    ];
    for (final active in [false, true]) {
      await tester.pumpWidget(
        plain(
          Center(
            child: ExploreCardIconButton(
              icon: Icons.bookmark_border,
              fillIcon: Icons.bookmark,
              semanticLabel: 'Save event',
              active: active,
              color: Ep.ink,
              iconShadows: shadows,
              onPressed: () {},
            ),
          ),
          brightness: Brightness.light,
        ),
      );
      final fill = tester.widget<Icon>(find.byIcon(Icons.bookmark));
      final outline = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
      expect(fill.color, Ep.ink.withValues(alpha: active ? 0.60 : 0.22));
      expect(fill.shadows, isNull);
      expect(outline.color, Ep.ink);
      expect(outline.shadows, shadows);
    }
  });

  testWidgets('ring actions stay unfilled in both themes and all states', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      for (final enabled in [false, true]) {
        for (final active in [false, true]) {
          await tester.pumpWidget(
            plain(
              Center(
                child: ExploreCardIconButton(
                  icon: Icons.bookmark_border,
                  fillIcon: Icons.bookmark,
                  semanticLabel: 'Save event',
                  ring: true,
                  active: active,
                  color: Ep.ink,
                  iconShadows: const [Shadow(color: Ep.background)],
                  onPressed: enabled ? () {} : null,
                ),
              ),
              brightness: brightness,
            ),
          );
          final button = find.byType(ExploreCardIconButton);
          final palette = tester.element(button).epColors;
          final outline = tester.widget<Icon>(
            find.byIcon(Icons.bookmark_border),
          );
          expect(find.byIcon(Icons.bookmark), findsNothing);
          expect(
            find.descendant(of: button, matching: find.byType(Stack)),
            findsNothing,
          );
          expect(
            outline.color,
            !enabled
                ? palette.contentDisabled
                : active
                ? palette.accent
                : palette.muted,
          );
          expect(outline.shadows, isNull);
          final ring = tester.widget<DecoratedBox>(
            find.descendant(of: button, matching: find.byType(DecoratedBox)),
          );
          final decoration = ring.decoration as ShapeDecoration;
          expect(decoration.color, isNull);
          expect(
            (decoration.shape as CircleBorder).side,
            BorderSide(color: palette.line, width: 1),
          );
        }
      }
    }
  });

  testWidgets('card icon button has a flush 36px ring and a 44px target', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      plain(
        Center(
          child: ExploreCardIconButton(
            icon: Icons.bookmark_border,
            fillIcon: Icons.bookmark,
            semanticLabel: 'Save event',
            ring: true,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    final button = find.byType(ExploreCardIconButton);
    final buttonRect = tester.getRect(button);
    final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
    final semantics = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Save event',
      ),
    );
    expect(buttonRect.size, const Size(36, 36));
    expect(tester.getSize(inkWell), const Size(44, 44));
    expect(tester.getRect(inkWell), buttonRect.inflate(4));
    expect(tester.getRect(semantics), buttonRect.inflate(4));
    final ring = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox && widget.decoration is ShapeDecoration,
      ),
    );
    final decoration =
        tester.widget<DecoratedBox>(ring).decoration as ShapeDecoration;
    expect(decoration.color, isNull);
    expect((decoration.shape as CircleBorder).side.width, 1);
    expect(tester.getRect(ring).top, closeTo(buttonRect.top, 0.5));
    expect(tester.getSize(ring), const Size(36, 36));
    await tester.tap(button);
    expect(taps, 1);
    for (final offset in const [
      Offset(-21, 0),
      Offset(21, 0),
      Offset(0, -21),
      Offset(0, 21),
    ]) {
      await tester.tapAt(buttonRect.center + offset);
    }
    expect(taps, 5);
  });

  testWidgets('circle action keeps its white glyph and 44px tap target', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      plain(
        Center(
          child: ExploreCardIconButton(
            icon: Icons.bookmark_border,
            fillIcon: Icons.bookmark,
            semanticLabel: 'Save event',
            circle: true,
            active: true,
            color: Ep.accent,
            iconShadows: const [Shadow(color: Ep.accent)],
            onPressed: () => taps++,
          ),
        ),
        brightness: Brightness.light,
      ),
    );
    final button = find.byType(ExploreCardIconButton);
    final buttonRect = tester.getRect(button);
    final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
    expect(buttonRect.size, const Size(36, 36));
    expect(tester.getRect(inkWell), buttonRect.inflate(4));
    final circle = find.descendant(
      of: button,
      matching: find.byType(DecoratedBox),
    );
    final decoration =
        tester.widget<DecoratedBox>(circle).decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, Ep.background);
    expect(decoration.border, isNull);
    expect(tester.getRect(circle), buttonRect);
    expect(
      find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox && widget.decoration is ShapeDecoration,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: button, matching: find.byType(Stack)),
      findsNothing,
    );
    expect(find.byIcon(Icons.bookmark), findsNothing);
    final glyph = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
    expect(glyph.size, 20);
    expect(glyph.color, Ep.ink);
    expect(glyph.shadows, isNull);
    expect(
      tester.getCenter(find.byIcon(Icons.bookmark_border)),
      buttonRect.center,
    );
    await tester.tap(button);
    for (final offset in const [
      Offset(-21, 0),
      Offset(21, 0),
      Offset(0, -21),
      Offset(0, 21),
    ]) {
      await tester.tapAt(buttonRect.center + offset);
    }
    expect(taps, 5);
  });

  testWidgets('ring and circle visuals are 36px with centered 44px targets', (
    tester,
  ) async {
    for (final ring in [true, false]) {
      await tester.pumpWidget(
        plain(
          Center(
            child: ExploreCardIconButton(
              icon: Icons.bookmark_border,
              semanticLabel: 'Save event',
              ring: ring,
              circle: !ring,
              onPressed: () {},
            ),
          ),
        ),
      );
      final button = find.byType(ExploreCardIconButton);
      final visual = find.descendant(
        of: button,
        matching: find.byType(DecoratedBox),
      );
      final target = find.descendant(
        of: button,
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(button), const Size(36, 36));
      expect(tester.getRect(visual), tester.getRect(button));
      expect(
        tester.getSize(find.byIcon(Icons.bookmark_border)),
        const Size(20, 20),
      );
      expect(tester.getSize(target), const Size(44, 44));
      expect(tester.getCenter(target), tester.getCenter(button));
    }
  });

  testWidgets('card actions receive overflow taps without opening the gig', (
    tester,
  ) async {
    final gig = gigFixture(id: 'action-hit-targets');
    for (final featured in [false, true]) {
      var saves = 0;
      var shares = 0;
      var opens = 0;
      final save = ExploreCardIconButton(
        key: const Key('hit-save'),
        icon: Icons.bookmark_border,
        fillIcon: Icons.bookmark,
        semanticLabel: 'Save event',
        ring: !featured,
        circle: featured,
        onPressed: () => saves++,
      );
      await tester.pumpWidget(
        plain(
          Center(
            child: SizedBox(
              width: 320,
              child: featured
                  ? ExploreFeaturedCard(
                      gig: gig,
                      venueName: 'The Foghorn',
                      lines: GigCardLines(
                        dateLine: 'WED, SEP 23 AT 8PM',
                        title: gig.title,
                        location: 'Southside · 11.2 mi',
                        price: gig.priceLabel,
                      ),
                      width: 320,
                      height: 200,
                      actions: [
                        ExploreCardIconButton(
                          key: const Key('hit-share'),
                          icon: Icons.ios_share,
                          semanticLabel: 'Share event',
                          circle: true,
                          onPressed: () => shares++,
                        ),
                        save,
                      ],
                      onTap: () => opens++,
                    )
                  : ExploreEventRow(
                      gig: gig,
                      venueName: 'The Foghorn',
                      lines: GigCardLines(
                        dateLine: 'WED, SEP 23 AT 8PM',
                        title: gig.title,
                        location: 'Southside · 11.2 mi',
                        price: gig.priceLabel,
                      ),
                      saveAction: save,
                      onTap: () => opens++,
                    ),
            ),
          ),
        ),
      );
      final saveRect = tester.getRect(find.byKey(const Key('hit-save')));
      for (final offset in [
        featured ? const Offset(21, 0) : const Offset(-21, 0),
        const Offset(0, -21),
        const Offset(0, 21),
      ]) {
        await tester.tapAt(saveRect.center + offset);
      }
      expect(saves, 3);
      if (featured) {
        final shareRect = tester.getRect(find.byKey(const Key('hit-share')));
        for (final offset in const [
          Offset(-21, 0),
          Offset(0, -21),
          Offset(0, 21),
        ]) {
          await tester.tapAt(shareRect.center + offset);
        }
        expect(shares, 3);
        // The overlapping part of the targets belongs to the nearest button.
        await tester.tapAt(shareRect.center + const Offset(21, 0));
        expect(saves, 4);
        expect(shares, 3);
      } else {
        await tester.tapAt(saveRect.center);
        expect(saves, 4);
        expect(shares, 0);
        expect(find.byIcon(Icons.ios_share), findsNothing);
      }
      expect(opens, 0);
      await tester.tap(find.text(gig.title.toUpperCase()));
      expect(opens, 1);
    }
  });

  testWidgets('disabled share button has only its outline and no ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      plain(
        const Center(
          child: ExploreCardIconButton(
            icon: Icons.ios_share,
            semanticLabel: 'Share event',
            onPressed: null,
          ),
        ),
      ),
    );
    final button = find.byType(ExploreCardIconButton);
    expect(
      find.descendant(of: button, matching: find.byType(Icon)),
      findsOneWidget,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.ios_share)).color,
      tester.element(button).epColors.contentDisabled,
    );
    expect(
      find.descendant(of: button, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    final semantics = tester.widget<Semantics>(
      find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'Share event',
        ),
      ),
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.enabled, isFalse);
  });

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
      expect(
        tileRect.height,
        closeTo(exploreVenueRailHeight(context), 0.01),
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

  testWidgets('event row shows three lines, generated flyer, and taps', (
    tester,
  ) async {
    var tapped = false;
    final gig = gigFixture(
      id: 'event-row',
      title: 'Neon Nights',
      startsAt: DateTime(2026, 9, 23),
    );
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          lines: GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: gig.title,
            location: 'Southside · 11.2 mi',
            price: gig.priceLabel,
          ),
          onTap: () => tapped = true,
        ),
      ),
    );
    expect(find.text('NEON NIGHTS'), findsOneWidget);
    expect(find.byType(GigFlyer), findsOneWidget);
    expect(find.text('NN'), findsNothing);
    expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
    expect(find.text('Southside · 11.2 mi'), findsOneWidget);
    expect(find.text('FREE'), findsOneWidget);
    final dateRect = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
    final titleRect = tester.getRect(find.text('NEON NIGHTS'));
    final locationRect = tester.getRect(find.text('Southside · 11.2 mi'));
    final priceRect = tester.getRect(
      find.byKey(ValueKey('gig-price-${gig.id}')),
    );
    expect(titleRect.top - dateRect.bottom, closeTo(8, 0.1));
    expect(priceRect.top - titleRect.bottom, closeTo(8, 0.1));
    expect(locationRect.center.dy, closeTo(priceRect.center.dy, 0.1));
    await tester.tap(find.text('NEON NIGHTS'));
    expect(tapped, isTrue);

    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gigFixture(id: 'paid-row', title: 'Paid Night', price: 12),
          venueName: 'The Foghorn',
          lines: const GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: 'Paid Night',
            location: 'Southside',
            price: '\$12',
          ),
          onTap: () {},
        ),
      ),
    );
    expect(find.textContaining('FREE'), findsNothing);
    expect(find.text('\$12'), findsOneWidget);
  });

  testWidgets(
    'paid price renders as plain text, free price renders as an accent badge',
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
        if (gig.free) {
          expect(price, isA<Container>());
          expect((price as Container).color, Ep.accent);
        } else {
          expect(price, isA<Text>());
          expect(price, isNot(isA<Container>()));
        }
      }
    },
  );

  testWidgets('cancelled event row shows the CANCELLED marker', (tester) async {
    final gig = gigFixture(
      id: 'cancelled-row',
      title: 'Cancelled Show',
      lifecycle: GigLifecycle.cancelled,
    );
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          lines: GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: gig.title,
            location: 'Southside · 11.2 mi',
            price: gig.priceLabel,
          ),
          onTap: () {},
        ),
      ),
    );
    expect(find.text('CANCELLED'), findsOneWidget);
    expect(find.byKey(ValueKey('gig-cancelled-${gig.id}')), findsOneWidget);
  });

  testWidgets('event row supports supplied lines, sub, and thumbnail size', (
    tester,
  ) async {
    final gig = gigFixture(id: 'custom-lines-row');
    const sub = 'Maya and Dev are going';
    await tester.pumpWidget(
      plain(
        ExploreEventRow(
          gig: gig,
          venueName: 'The Foghorn',
          lines: GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: gig.title,
            location: 'Southside · 11.2 mi',
            price: gig.priceLabel,
          ),
          sub: sub,
          thumbnailSize: 72.5,
          onTap: () {},
        ),
      ),
    );
    final dateText = tester.widget<Text>(find.text('WED, SEP 23 AT 8PM'));
    expect(dateText.maxLines, 1);
    expect(dateText.overflow, TextOverflow.ellipsis);
    expect(find.textContaining('The Foghorn'), findsNothing);
    final subText = tester.widget<Text>(find.text(sub));
    expect(subText.maxLines, 1);
    expect(subText.overflow, TextOverflow.ellipsis);
    expect(
      subText.style?.color,
      tester.element(find.byType(ExploreEventRow)).epColors.muted,
    );
    expect(
      tester.getRect(find.text(sub)).top,
      greaterThan(
        tester.getRect(find.byKey(ValueKey('gig-price-${gig.id}'))).bottom,
      ),
    );
    final thumbnail = find.byType(EpNetworkImage);
    final thumbnailSize = tester.getSize(thumbnail);
    final rowHeight = tester.getSize(find.byType(ExploreEventRow)).height;
    expect(thumbnailSize.width, 72.5);
    expect(thumbnailSize.height, closeTo(rowHeight - 25, 0.1));
    final image = tester.widget<EpNetworkImage>(thumbnail);
    expect(image.cacheWidth, 73);
    expect(image.cacheHeight, isNull);
  });

  testWidgets('event row thumbnail matches its natural text column height', (
    tester,
  ) async {
    for (final title in [
      'Live Music',
      'A Long Event Title That Wraps Across Several Lines',
    ]) {
      final gig = gigFixture(id: 'content-height-row', title: title);
      await tester.pumpWidget(
        plain(
          SizedBox(
            width: 320,
            child: ExploreEventRow(
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
        ),
      );
      final thumbnail = find.byType(EpNetworkImage);
      final textColumn = find.descendant(
        of: find.byType(ExploreEventRow),
        matching: find.byWidgetPredicate(
          (widget) => widget is Expanded && widget.child is Column,
        ),
      );
      final thumbnailRect = tester.getRect(thumbnail);
      final textRect = tester.getRect(textColumn);
      final dateRect = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
      final priceRect = tester.getRect(
        find.byKey(ValueKey('gig-price-${gig.id}')),
      );
      expect(thumbnailRect.width, 96);
      expect(thumbnailRect.height, closeTo(textRect.height, 0.1));
      expect(thumbnailRect.top, closeTo(textRect.top, 0.1));
      expect(textRect.top, closeTo(dateRect.top, 0.1));
      expect(textRect.bottom, closeTo(priceRect.bottom, 0.1));
      expect(tester.widget<EpNetworkImage>(thumbnail).fit, BoxFit.cover);
      expect(tester.takeException(), isNull);
    }
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
            ExploreEventRow(
              gig: gig,
              venueName: 'The Foghorn',
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
              venueName: 'The Foghorn',
              lines: GigCardLines(
                dateLine: 'WED, SEP 23 AT 8PM',
                title: gig.title,
                location: 'Southside · 11.2 mi',
                price: gig.priceLabel,
              ),
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

  testWidgets('event row puts its save action at the end of the date line', (
    tester,
  ) async {
    final gig = gigFixture(id: 'poster-actions', title: 'Live Music');
    for (final scale in [1.0, 1.5]) {
      await tester.pumpWidget(
        plain(
          SizedBox(
            width: 300,
            child: ExploreEventRow(
              gig: gig,
              venueName: 'The Foghorn',
              lines: GigCardLines(
                dateLine: 'WED, SEP 23 AT 8PM',
                title: gig.title,
                location: 'Southside · 11.2 mi',
                price: gig.priceLabel,
              ),
              saveAction: ExploreCardIconButton(
                key: const Key('poster-save'),
                icon: Icons.bookmark_border,
                semanticLabel: 'Save event',
                ring: true,
                onPressed: () {},
              ),
              onTap: () {},
            ),
          ),
          textScaler: TextScaler.linear(scale),
        ),
      );
      final row = tester.getRect(find.byType(ExploreEventRow));
      final date = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
      final action = tester.getRect(find.byKey(const Key('poster-save')));
      expect(action.top, closeTo(date.top, 0.1));
      expect(date.right, lessThanOrEqualTo(action.left + 0.1));
      expect(action.right, closeTo(row.right, 0.1));
      expect(tester.takeException(), isNull, reason: 'scale $scale');
    }
  });

  testWidgets('event row never renders a chevron or share action', (
    tester,
  ) async {
    final gig = gigFixture(id: 'actions-no-chevron', title: 'Action Event');
    for (final withSave in [false, true]) {
      await tester.pumpWidget(
        plain(
          ExploreEventRow(
            gig: gig,
            venueName: 'The Foghorn',
            lines: GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: gig.title,
              location: 'Southside · 11.2 mi',
              price: gig.priceLabel,
            ),
            saveAction: withSave
                ? ExploreCardIconButton(
                    icon: Icons.bookmark_border,
                    semanticLabel: 'Save event',
                    ring: true,
                    onPressed: () {},
                  )
                : null,
            onTap: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byIcon(Icons.ios_share), findsNothing);
    }
  });

  testWidgets('compact fan card keeps save and the optional QR action', (
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
              onPressed: () => qrTaps++,
            ),
          ),
        ),
      ),
    );
    final save = find.byKey(ValueKey('save-${gig.id}'));
    expect(tester.widget<ExploreCardIconButton>(save).ring, isTrue);
    expect(tester.getSize(save), const Size(36, 36));
    final actions = tester.widget<Wrap>(
      find.byKey(ValueKey('event-actions-${gig.id}')),
    );
    expect(actions.children, hasLength(2));
    expect(find.byKey(ValueKey('share-${gig.id}')), findsNothing);
    expect(find.byIcon(Icons.ios_share), findsNothing);
    expect(
      tester.getRect(save).top,
      closeTo(tester.getRect(find.text('WED, SEP 23 AT 8PM')).top, 0.1),
    );
    await tester.tap(find.byKey(const Key('qr-action')));
    expect(qrTaps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('event row wraps a long title with the original date gap', (
    tester,
  ) async {
    const title =
        'A Very Long Event Title That Must Wrap Within A Narrow Card Width';
    final gig = gigFixture(id: 'long-title-actions', title: title, price: 15);
    for (final scale in [1.0, 1.5]) {
      await tester.pumpWidget(
        plain(
          SizedBox(
            width: 300,
            child: ExploreEventRow(
              gig: gig,
              venueName: 'The Foghorn',
              lines: GigCardLines(
                dateLine: 'WED, SEP 23 AT 8PM',
                title: gig.title,
                location: 'Southside · 11.2 mi',
                price: gig.priceLabel,
              ),
              saveAction: ExploreCardIconButton(
                icon: Icons.bookmark_border,
                semanticLabel: 'Save event',
                ring: true,
                onPressed: () {},
              ),
              onTap: () {},
            ),
          ),
          textScaler: TextScaler.linear(scale),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      final titleFinder = find.text(title.toUpperCase());
      final titleText = tester.widget<Text>(titleFinder);
      expect(tester.getSize(titleFinder).height, greaterThan(24));
      expect(titleText.softWrap, isTrue);
      expect(titleText.style?.fontSize, 18);
      expect(titleText.overflow, TextOverflow.clip);
      final titleRect = tester.getRect(titleFinder);
      final dateRect = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
      expect(titleRect.top - dateRect.bottom, closeTo(8, 0.1));
      expect(titleRect.left, closeTo(dateRect.left, 0.1));
      final buttonRect = tester.getRect(find.byType(ExploreCardIconButton));
      expect(titleRect.right, lessThanOrEqualTo(buttonRect.left + 0.1));
      expect(find.byType(ExploreLineupRow), findsNothing);
    }
  });

  testWidgets(
    'event row uses a regular mono date, muted location, and plain paid price',
    (tester) async {
      final gig = gigFixture(id: 'structured-lines', price: 12);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          plain(
            ExploreEventRow(
              gig: gig,
              venueName: 'The Foghorn',
              lines: GigCardLines(
                dateLine: 'WED, SEP 23 AT 8PM',
                title: gig.title,
                location: 'Southside · 11.2 mi',
                price: gig.priceLabel,
              ),
              onTap: () {},
            ),
            brightness: brightness,
          ),
        );
        final row = find.byType(ExploreEventRow);
        final palette = tester.element(row).epColors;
        final date = tester.widget<Text>(find.text('WED, SEP 23 AT 8PM'));
        expect(date.textSpan, isNull);
        expect(date.style?.fontFamily, 'Azeret Mono');
        expect(date.style?.fontSize, 11);
        expect(date.style?.fontWeight, FontWeight.w400);
        expect(date.style?.color, palette.muted);
        expect(date.maxLines, 1);
        expect(date.overflow, TextOverflow.ellipsis);
        final location = tester.widget<Text>(find.text('Southside · 11.2 mi'));
        expect(
          location.style,
          Theme.of(
            tester.element(row),
          ).textTheme.epCaption.copyWith(color: palette.muted),
        );
        expect(location.maxLines, 1);
        expect(location.overflow, TextOverflow.ellipsis);
        final price = tester.widget(
          find.byKey(ValueKey('gig-price-${gig.id}')),
        );
        expect(price, isA<Text>());
        expect(price, isNot(isA<Container>()));
        final label = price as Text;
        expect(label.data, '\$12');
        expect(label.textAlign, TextAlign.right);
        expect(label.style?.fontFamily, 'Azeret Mono');
        expect(label.style?.fontSize, 13);
        expect(label.style?.color, palette.ink);
        expect(tester.takeException(), isNull);
      }
    },
  );

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
          lines: const GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: 'featured-no-ticket',
            location: 'Southside',
            price: 'FREE',
          ),
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(EpPill), findsNothing);
  });

  testWidgets(
    'featured card renders three lines and price without date blocks or lineup',
    (tester) async {
      const lines = GigCardLines(
        dateLine: 'WED, SEP 23 AT 8PM',
        title: 'Featured Event',
        location: 'Southside · 11.2 mi',
        price: 'free',
      );
      final gig = gigFixture(id: 'featured-lines', title: lines.title);
      await tester.pumpWidget(
        plain(
          ExploreFeaturedCard(
            gig: gig,
            venueName: 'The Foghorn',
            lines: lines,
            onTap: () {},
            width: 334,
            height: 200,
          ),
        ),
      );
      expect(find.text(lines.dateLine), findsOneWidget);
      expect(find.text(lines.title.toUpperCase()), findsOneWidget);
      expect(find.text(lines.location), findsOneWidget);
      expect(find.text('FREE'), findsOneWidget);
      expect(find.byKey(ValueKey('gig-price-${gig.id}')), findsOneWidget);
      expect(find.byType(EpDateBlock), findsNothing);
      expect(find.byType(ExploreLineupRow), findsNothing);
      expect(find.byType(ExploreLineupWrap), findsNothing);
      expect(find.byType(EpAvatarTile), findsNothing);
      final date = tester.getRect(find.text(lines.dateLine));
      final title = tester.getRect(find.text(lines.title.toUpperCase()));
      final location = tester.getRect(find.text(lines.location));
      final price = tester.getRect(find.byKey(ValueKey('gig-price-${gig.id}')));
      expect(title.top - date.bottom, closeTo(8, 0.1));
      expect(price.top - title.bottom, closeTo(6, 0.1));
      expect(location.center.dy, closeTo(price.center.dy, 0.1));
    },
  );

  testWidgets(
    'featured three-line typography and price match in both layouts',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final flyKey in ['paper', 'panel']) {
          for (final size in [const Size(300, 380), const Size(334, 200)]) {
            final gig = gigFixture(
              id: 'featured-styles',
              title: 'Featured Event',
              flyKey: flyKey,
            );
            await tester.pumpWidget(
              plain(
                ExploreFeaturedCard(
                  gig: gig,
                  venueName: 'The Foghorn',
                  lines: GigCardLines(
                    dateLine: 'WED, SEP 23 AT 8PM',
                    title: gig.title,
                    location: 'Southside · 11.2 mi',
                    price: gig.priceLabel,
                  ),
                  onTap: () {},
                  width: size.width,
                  height: size.height,
                ),
                brightness: brightness,
              ),
            );
            final date = tester.widget<Text>(find.text('WED, SEP 23 AT 8PM'));
            expect(date.style?.fontFamily, 'Azeret Mono');
            expect(date.style?.fontSize, 12);
            expect(date.style?.fontWeight, FontWeight.w400);
            expect(date.style?.color, Ep.ink.withValues(alpha: 0.72));
            expect(date.maxLines, 1);
            expect(date.overflow, TextOverflow.ellipsis);
            final display = tester.widget<EpDisplay>(find.byType(EpDisplay));
            expect(display.text, gig.title);
            expect(display.size, 24);
            expect(display.maxLines, 2);
            expect(display.overflow, TextOverflow.ellipsis);
            expect(display.color, Ep.ink);
            final location = tester.widget<Text>(
              find.text('Southside · 11.2 mi'),
            );
            expect(location.style?.fontFamily, 'PP Telegraf');
            expect(location.style?.fontSize, 14);
            expect(location.style?.color, Ep.ink.withValues(alpha: 0.85));
            expect(location.maxLines, 1);
            expect(location.overflow, TextOverflow.ellipsis);
            final price = tester.widget<Container>(
              find.byKey(ValueKey('gig-price-${gig.id}')),
            );
            expect(price.color, Ep.accent);
            expect(price.decoration, isNull);
            expect(
              price.padding,
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            );
            final label = price.child! as Text;
            expect(label.data, 'FREE');
            expect(label.style?.fontFamily, 'Azeret Mono');
            expect(label.style?.fontSize, 13);
            expect(label.style?.color, Ep.ink);
            final scrim = tester.widget<DecoratedBox>(
              find.descendant(
                of: find.byType(ExploreFeaturedCard),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is DecoratedBox &&
                      widget.decoration is BoxDecoration &&
                      (widget.decoration as BoxDecoration).gradient
                          is LinearGradient,
                ),
              ),
            );
            final gradient =
                (scrim.decoration as BoxDecoration).gradient! as LinearGradient;
            expect(gradient.colors, [
              Ep.background.withValues(alpha: 0),
              Ep.background.withValues(alpha: .94),
            ]);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets(
    'featured fan actions use black circles and white glyphs for every artwork',
    (tester) async {
      for (final artwork in [
        (flyKey: 'paper', url: null),
        (flyKey: 'panel', url: ''),
        (flyKey: 'accent', url: null),
        (flyKey: 'unknown', url: null),
        (flyKey: 'paper', url: 'https://example.com/flyer.jpg'),
      ]) {
        final gig = gigFixture(
          id: 'featured-action-contrast',
          title: 'Featured Event',
          startsAt: DateTime(2026, 9, 23),
          flyKey: artwork.flyKey,
          flyerUrl: artwork.url,
        );
        await pumpApp(
          tester,
          home: Scaffold(
            body: Consumer<AppState>(
              builder: (context, app, _) => FanEventCard(
                gig: gig,
                app: app,
                presentation: FanEventCardPresentation.featured,
              ),
            ),
          ),
        );
        expect(find.byKey(ValueKey('fan-event-${gig.id}')), findsOneWidget);
        for (final action in ['share', 'save']) {
          final button = find.byKey(ValueKey('$action-${gig.id}'));
          final widget = tester.widget<ExploreCardIconButton>(button);
          expect(widget.circle, isTrue);
          expect(widget.ring, isFalse);
          final glyph = tester.widget<Icon>(
            find.descendant(of: button, matching: find.byType(Icon)),
          );
          expect(glyph.color, Ep.ink);
          expect(glyph.size, 20);
          expect(glyph.shadows, isNull);
          final circle = tester.widget<DecoratedBox>(
            find.descendant(of: button, matching: find.byType(DecoratedBox)),
          );
          final decoration = circle.decoration as BoxDecoration;
          expect(decoration.color, Ep.background);
          expect(decoration.shape, BoxShape.circle);
          expect(decoration.border, isNull);
        }
        expect(find.byIcon(Icons.bookmark), findsNothing);
        expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
        expect(find.text('FREE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

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
        ExploreFeaturedCard(
          gig: gig,
          venueName: 'The Foghorn',
          lines: GigCardLines(
            dateLine: 'WED, SEP 23 AT 8PM',
            title: gig.title,
            location: 'Southside · 11.2 mi',
            price: gig.priceLabel,
          ),
          onTap: () {},
        ),
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
    expect(
      find.descendant(
        of: find.byType(ExploreFeaturedCard),
        matching: find.byType(EpDateBlock),
      ),
      findsNothing,
    );
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
            lines: const GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: 'A Long Featured Event Title',
              location: 'Southside',
              price: 'FREE',
            ),
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.text('A LONG FEATURED EVENT TITLE'), findsOneWidget);
      expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
      expect(find.text('Southside'), findsOneWidget);
      expect(find.text('RSVP'), findsNothing);
      expect(find.text('TICKETS'), findsNothing);
      expect(find.text('GOING'), findsNothing);
      await tester.tap(find.text('A LONG FEATURED EVENT TITLE'));
    }
    expect(tapped, isTrue);
  });

  testWidgets(
    'featured circle actions sit at the top-right with a four-pixel gap',
    (tester) async {
      final gig = gigFixture(
        id: 'featured-action-corners',
        title: 'Live Music',
      );
      for (final width in [360.0, 240.0]) {
        await tester.pumpWidget(
          plain(
            Center(
              child: ExploreFeaturedCard(
                gig: gig,
                venueName: 'The Foghorn',
                lines: GigCardLines(
                  dateLine: 'WED, SEP 23 AT 8PM',
                  title: gig.title,
                  location: 'Southside · 11.2 mi',
                  price: gig.priceLabel,
                ),
                width: width,
                height: 180,
                actions: [
                  ExploreCardIconButton(
                    key: const Key('featured-share'),
                    icon: Icons.ios_share,
                    semanticLabel: 'Share event',
                    circle: true,
                    onPressed: () {},
                  ),
                  ExploreCardIconButton(
                    key: const Key('featured-save'),
                    icon: Icons.bookmark_border,
                    fillIcon: Icons.bookmark,
                    semanticLabel: 'Save event',
                    circle: true,
                    onPressed: () {},
                  ),
                ],
                onTap: () {},
              ),
            ),
            textScaler: TextScaler.linear(1.5),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'width $width');
        final card = tester.getRect(find.byType(ExploreFeaturedCard));
        final save = tester.getRect(find.byKey(const Key('featured-save')));
        final share = tester.getRect(find.byKey(const Key('featured-share')));
        for (final action in [save, share]) {
          expect(action.top - card.top, closeTo(8, 0.1));
          expect(action.size, const Size(36, 36));
        }
        expect(card.right - save.right, closeTo(8, 0.1));
        expect(save.left - share.right, closeTo(4, 0.1));
      }
    },
  );

  testWidgets('landscape featured card fits its three lines at 1.0 and 1.5', (
    tester,
  ) async {
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
            lines: GigCardLines(
              dateLine: 'WED, SEP 23 AT 8PM',
              title: gig.title,
              location: 'Southside · 11.2 mi',
              price: gig.priceLabel,
            ),
            onTap: () {},
            width: 334,
            height: 200,
          ),
          textScaler: TextScaler.linear(scale),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      final card = tester.getRect(find.byType(ExploreFeaturedCard));
      expect(card.size, const Size(334, 200));
      expect(find.text(gig.title.toUpperCase()), findsOneWidget);
      expect(find.text('WED, SEP 23 AT 8PM'), findsOneWidget);
      expect(find.text('Southside · 11.2 mi'), findsOneWidget);
      expect(find.text('TICKETS'), findsNothing);
      final date = tester.getRect(find.text('WED, SEP 23 AT 8PM'));
      final price = tester.getRect(find.byKey(ValueKey('gig-price-${gig.id}')));
      expect(date.top, greaterThanOrEqualTo(card.top));
      expect(price.bottom, lessThanOrEqualTo(card.bottom - 16));
    }
  });

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
      ExploreLocationRow(label: 'A Location With A Long Name', onTap: () {}),
    ]) {
      debugPrint('scale child: ${child.runtimeType}');
      await tester.pumpWidget(plain(child, textScaler: scaler));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
}
