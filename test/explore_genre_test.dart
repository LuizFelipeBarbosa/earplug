import 'dart:ui' show PointerDeviceKind;

import 'package:earplug/app_state.dart';
import 'package:earplug/explore_ranking.dart';
import 'package:earplug/models.dart';
import 'package:earplug/theme.dart';
import 'package:earplug/widgets/ep_carousel.dart';
import 'package:earplug/widgets/ep_text.dart';
import 'package:earplug/widgets/explore_genres.dart';
import 'package:earplug/widgets/explore_tiles.dart';
import 'package:earplug/widgets/feed_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/fixtures.dart';
import 'support/harness.dart';

Widget _rail({
  String? selected,
  ValueChanged<String?>? onSelect,
  int count = 3,
}) {
  final chips = [
    for (var i = 0; i < count; i++)
      GenreChip(genre: 'genre-$i', label: 'Genre $i', feedCount: i + 1),
  ];
  return ExploreGenreRail(
    chips: chips,
    selected: selected,
    onSelect: onSelect ?? (_) {},
  );
}

Future<void> _pumpRail(WidgetTester tester, Widget rail, {double scale = 1}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildEpTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: rail,
        ),
      ),
    ),
  );
}

ExploreGenrePage _page({
  List<Gig> tonight = const [],
  List<Gig> week = const [],
  List<Gig> later = const [],
  List<String> bandIds = const [],
}) => ExploreGenrePage(
  genre: 'punk',
  label: 'Punk',
  tonight: tonight,
  week: week,
  later: later,
  bandIds: bandIds,
);

Widget _textBandTile(String id) => Text(id);

void main() {
  testWidgets('rail renders All and chips in order with feed counts', (
    tester,
  ) async {
    await _pumpRail(tester, _rail());

    expect(find.text('ALL'), findsOneWidget);
    expect(find.text('GENRE 0 · 1'), findsOneWidget);
    expect(find.text('GENRE 1 · 2'), findsOneWidget);
    expect(find.text('GENRE 2 · 3'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('feed-genre-genre-0'))).dx,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('feed-genre-genre-1'))).dx,
      ),
    );
  });

  testWidgets('rail selection and re-tap clear selection', (tester) async {
    String? selected;
    final selections = <String?>[];
    await _pumpRail(
      tester,
      StatefulBuilder(
        builder: (context, setState) => ExploreGenreRail(
          chips: const [GenreChip(genre: 'punk', label: 'Punk', feedCount: 1)],
          selected: selected,
          onSelect: (value) {
            selections.add(value);
            setState(() => selected = value);
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('feed-genre-punk')));
    await tester.pump();
    expect(selections, ['punk']);
    expect(
      tester
          .widget<EpPill>(find.byKey(const Key('feed-genre-punk')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('feed-genre-punk')));
    expect(selections, ['punk', null]);
  });

  testWidgets('rail scrolls with a mouse drag', (tester) async {
    await _pumpRail(tester, SizedBox(width: 300, child: _rail(count: 10)));
    final item = find.byKey(const Key('feed-genre-genre-0'));
    final before = tester.getTopLeft(item).dx;
    await tester.drag(
      find.byType(ListView),
      const Offset(-200, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(tester.getTopLeft(item).dx, lessThan(before));
  });

  testWidgets('body groups buckets and preserves gig order', (tester) async {
    final gigs = [
      gigFixture(id: 'tonight-1'),
      gigFixture(id: 'week-1'),
      gigFixture(id: 'later-1'),
    ];
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            child: ExploreGenrePageBody(
              page: _page(
                tonight: [gigs[0]],
                week: [gigs[1]],
                later: [gigs[2]],
              ),
              app: context.read<AppState>(),
              bandTile: _textBandTile,
              onAllBands: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('TONIGHT · 1'), findsOneWidget);
    expect(find.text('THIS WEEK · 1'), findsOneWidget);
    expect(find.text('LATER · 1'), findsOneWidget);
    final tonightHeader = tester.getTopLeft(find.text('TONIGHT · 1')).dy;
    final weekHeader = tester.getTopLeft(find.text('THIS WEEK · 1')).dy;
    final laterHeader = tester.getTopLeft(find.text('LATER · 1')).dy;
    expect(tonightHeader, lessThan(weekHeader));
    expect(weekHeader, lessThan(laterHeader));
    expect(find.byKey(const Key('fan-event-tonight-1')), findsOneWidget);
    expect(find.byKey(const Key('fan-event-week-1')), findsOneWidget);
    expect(find.byKey(const Key('fan-event-later-1')), findsOneWidget);
  });

  testWidgets('body empty state still renders bands and actions', (
    tester,
  ) async {
    var bandTiles = 0;
    var allBandsTapped = false;
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: SingleChildScrollView(
            child: ExploreGenrePageBody(
              page: _page(bandIds: const ['b1', 'b2']),
              app: context.read<AppState>(),
              bandTile: (id) {
                bandTiles++;
                return SizedBox(key: ValueKey('band-tile-$id'));
              },
              onAllBands: () => allBandsTapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('No Punk shows in the loaded feed.'), findsOneWidget);
    expect(find.byKey(const Key('explore-genre-widen')), findsOneWidget);
    expect(find.byKey(const Key('band-tile-b1')), findsOneWidget);
    expect(find.byKey(const Key('band-tile-b2')), findsOneWidget);
    expect(bandTiles, 2);
    // Shared gaps surround the heading; the rail fits the tallest band tile
    // and the All bands row follows the rail directly.
    final heading = find.text('BANDS PLAYING PUNK');
    final widen = find.byKey(const Key('explore-genre-widen'));
    expect(
      tester.getTopLeft(heading).dy - tester.getRect(widen).bottom,
      kFeedSectionGap,
    );
    final rail = find.byType(EpCarousel);
    final railRect = tester.getRect(rail);
    expect(
      railRect.top - tester.getRect(heading).bottom,
      closeTo(kFeedHeaderGap, 1),
    );
    expect(railRect.height, exploreBandRailHeight(tester.element(rail)));
    final allBands = find.byKey(const Key('explore-toggle-bands'));
    expect(tester.getTopLeft(allBands).dy, railRect.bottom);
    await tester.tap(allBands);
    expect(allBandsTapped, isTrue);
  });

  testWidgets('rail and body fit at text scale 1.5', (tester) async {
    await _pumpRail(
      tester,
      SizedBox(width: 400, child: _rail(count: 8)),
      scale: 1.5,
    );
    expect(tester.takeException(), isNull);

    await pumpApp(
      tester,
      size: const Size(400, 900),
      home: Builder(
        builder: (context) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: ExploreGenrePageBody(
                page: _page(
                  tonight: [gigFixture(id: 'scaled')],
                  bandIds: const ['b1', 'b2', 'b3'],
                ),
                app: context.read<AppState>(),
                bandTile: (id) => SizedBox(key: ValueKey(id), height: 80),
                onAllBands: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
