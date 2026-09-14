import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../explore_ranking.dart';
import '../models.dart';
import '../theme.dart';
import 'ep_carousel.dart';
import 'ep_rows.dart';
import 'ep_text.dart';
import 'explore_tiles.dart';
import 'fan_event_card.dart';

/// A sideways-scrollable rail of genre chips: "All" plus one chip per genre.
/// Mouse-draggable. Sits under the quick filters in the Explore page header.
class ExploreGenreRail extends StatelessWidget {
  const ExploreGenreRail({
    super.key,
    required this.chips,
    required this.selected,
    required this.onSelect,
    this.padding = const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
  });

  final List<GenreChip> chips;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('explore-genre-rail'),
    height: 40,
    child: Semantics(
      container: true,
      label: 'Genres',
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
          },
          scrollbars: false,
        ),
        child: ListView.separated(
          key: const Key('explore-genre-rail-list'),
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: chips.length + 1,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return EpPill(
                key: const Key('explore-genre-all'),
                label: 'All',
                size: EpPillSize.chip,
                selected: selected == null,
                onPressed: () => onSelect(null),
              );
            }
            final chip = chips[index - 1];
            return EpPill(
              key: Key('explore-genre-${chip.genre}'),
              label: chip.feedCount > 0
                  ? '${chip.label} · ${chip.feedCount}'
                  : chip.label,
              size: EpPillSize.chip,
              selected: chip.genre == selected,
              onPressed: () =>
                  onSelect(chip.genre == selected ? null : chip.genre),
            );
          },
        ),
      ),
    ),
  );
}

/// The genre-mode body: heading, events grouped by day bucket, a bands rail,
/// and an empty state. Built as a plain Column so a page lane can embed it in
/// its own scroll view.
class ExploreGenrePageBody extends StatelessWidget {
  const ExploreGenrePageBody({
    super.key,
    required this.page,
    required this.app,
    required this.bandTile,
    required this.onAllBands,
  });

  final ExploreGenrePage page;
  final AppState app;
  final Widget Function(String bandId) bandTile;
  final VoidCallback onAllBands;

  @override
  Widget build(BuildContext context) {
    final gigPhrase = page.gigCount == 1
        ? '${page.gigCount} show'
        : '${page.gigCount} shows';
    final bandPhrase = page.bandIds.length == 1
        ? '${page.bandIds.length} band'
        : '${page.bandIds.length} bands';
    final children = <Widget>[
      const SizedBox(height: 24),
      EpDisplay(page.label, size: 36),
      EpEyebrow('$gigPhrase · $bandPhrase'),
    ];

    if (page.gigCount == 0) {
      children.addAll([
        Text(
          'No ${page.label} shows in the loaded feed.',
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        EpPill(
          key: const Key('explore-genre-widen'),
          label: 'Widen date filter',
          onPressed: app.widenDateFilter,
        ),
      ]);
    } else {
      _addBucket(children, 'Tonight', page.tonight);
      _addBucket(children, 'This week', page.week);
      _addBucket(children, 'Later', page.later);
    }

    if (page.bandIds.isNotEmpty) {
      children.addAll([
        EpSectionHeader(
          label: 'Bands playing ${page.label.toUpperCase()}',
          padding: const EdgeInsets.only(top: 32, bottom: 4),
        ),
        // Same extent as the browse page's BANDS rail: sized to the tile's
        // tallest content so no dead space opens up above the All bands row.
        EpCarousel(
          itemExtent: 120,
          height: exploreBandRailHeight(context),
          wrapWhenScaled: true,
          itemCount: page.bandIds.length,
          itemBuilder: (context, index) => bandTile(page.bandIds[index]),
        ),
      ]);
    }

    children.add(
      EpMenuRow(
        key: const Key('explore-toggle-bands'),
        icon: Icons.groups_outlined,
        label: 'All bands',
        onTap: onAllBands,
      ),
    );

    return Column(
      key: const Key('explore-genre-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  void _addBucket(List<Widget> children, String label, List<Gig> gigs) {
    if (gigs.isEmpty) return;
    children.add(EpSectionHeader(label: '$label · ${gigs.length}'));
    children.addAll(
      gigs.map((gig) => FanEventCard(gig: gig, app: app, showDistance: true)),
    );
  }
}
