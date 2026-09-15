import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_carousel.dart';
import 'ep_rows.dart';
import 'ep_text.dart';
import 'explore_genres.dart';
import 'explore_tiles.dart';
import 'fan_event_card.dart';

class DiscoveryFeed extends StatefulWidget {
  const DiscoveryFeed({super.key});

  @override
  State<DiscoveryFeed> createState() => _DiscoveryFeedState();
}

class _DiscoveryFeedState extends State<DiscoveryFeed> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().ensureSocial();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final modeKey = app.exploreGenrePage != null
        ? ValueKey('feed-genre-${app.exploreGenre}')
        : const ValueKey('feed-browse-all');
    return SafeArea(
      top: false,
      bottom: false,
      child: CustomScrollView(key: modeKey, slivers: _slivers(context, app)),
    );
  }

  List<Widget> _slivers(BuildContext context, AppState app) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    // 12px above and below the 40px chip row, then the hairline. The top gap
    // keeps the chips off the viewport edge once the header is pinned.
    final baseExtent = (12 + 40 + 12 + 1) * scale;
    final maxHeader = MediaQuery.sizeOf(context).height * .45;
    final pinRail = baseExtent <= maxHeader;
    final extent = pinRail ? baseExtent : 1 * scale;
    final controls = DecoratedBox(
      decoration: BoxDecoration(color: context.epColors.background),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pinRail) ...[
            const SizedBox(height: 12),
            ExploreGenreRail(
              chips: app.exploreGenres,
              selected: app.exploreGenre,
              onSelect: app.setExploreGenre,
            ),
            const SizedBox(height: 12),
          ],
          const EpHairline(),
        ],
      ),
    );
    final slivers = <Widget>[
      SliverPersistentHeader(
        pinned: true,
        delegate: _PinnedGenreRail(child: controls, extent: extent),
      ),
    ];
    if (!pinRail) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ExploreGenreRail(
              chips: app.exploreGenres,
              selected: app.exploreGenre,
              onSelect: app.setExploreGenre,
            ),
          ),
        ),
      );
    }
    final page = app.exploreGenrePage;
    if (page != null) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
            child: ExploreGenrePageBody(
              page: page,
              app: app,
              bandTile: (id) => switch (app.band(id)) {
                final band? => ExploreBandTile(
                  key: Key('explore-band-card-$id'),
                  band: band,
                  onTap: () => app.openBand(id),
                ),
                null => const SizedBox.shrink(),
              },
              onAllBands: () => app.go(Screen.exploreCollection, 'bands'),
            ),
          ),
        ),
      );
    } else {
      final home = app.exploreHome;
      if (home.featured.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: _gutter(EpSectionHeader(label: 'FEATURED')),
          ),
        );
        slivers.add(
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // One landscape card spans the width, leaving a sliver of
                // the next card visible so the rail reads as a carousel.
                const peek = 36.0;
                final extent = (constraints.maxWidth - EpLayout.gutter - peek)
                    .clamp(240.0, 640.0);
                final height = (extent * 0.6).roundToDouble();
                return EpCarousel(
                  key: const Key('feed-featured'),
                  itemExtent: extent,
                  height: height,
                  wrapWhenScaled: true,
                  itemCount: home.featured.length,
                  itemBuilder: (_, i) {
                    final gig = home.featured[i];
                    return FanEventCard(
                      key: Key('feed-featured-${gig.id}'),
                      rowKey: Key('feed-featured-${gig.id}'),
                      gig: gig,
                      app: app,
                      presentation: FanEventCardPresentation.featured,
                      showDistance: true,
                    );
                  },
                );
              },
            ),
          ),
        );
      }
      slivers.add(
        SliverToBoxAdapter(
          child: _gutter(
            EpSectionHeader(label: 'JUST FOR YOU · ${home.forYou.length}'),
          ),
        ),
      );
      if (home.forYou.isNotEmpty) {
        slivers.add(
          SliverList.builder(
            itemCount: home.forYou.length,
            itemBuilder: (_, i) {
              final gig = home.forYou[i];
              return _gutter(
                FanEventCard(
                  gig: gig,
                  app: app,
                  showDistance: true,
                  rowKey: Key('feed-for-you-${gig.id}'),
                ),
              );
            },
          ),
        );
      } else if (home.featured.isEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: _gutter(
              Text(
                'No upcoming events yet.',
                key: const Key('feed-empty'),
                style: Theme.of(
                  context,
                ).textTheme.epBody.copyWith(color: context.epColors.muted),
              ),
            ),
          ),
        );
      }
      final venues = home.venues;
      if (venues.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: _gutter(
              EpSectionHeader(
                label: 'VENUES',
                action: 'See more',
                actionKey: const Key('feed-toggle-venues'),
                onAction: () => app.go(Screen.exploreCollection, 'venues'),
              ),
            ),
          ),
        );
        slivers.add(
          SliverToBoxAdapter(
            child: EpCarousel(
              key: const Key('feed-venues'),
              itemExtent: 220,
              height: exploreVenueRailHeight(context),
              wrapWhenScaled: true,
              itemCount: venues.length,
              itemBuilder: (_, i) {
                final entry = venues[i];
                return ExploreVenueTile(
                  key: Key('explore-venue-tile-${entry.venue.id}'),
                  entry: entry,
                  width: 220,
                  distance: app.distanceOf(entry.venue),
                  onTap: () => app.openVenue(entry.venue.id),
                );
              },
            ),
          ),
        );
      }
      final bandIds = <String>[];
      for (final id in [...home.recommendedBandIds, ...app.exploreBandIds]) {
        if (!bandIds.contains(id) && app.band(id) != null) bandIds.add(id);
        if (bandIds.length == 16) break;
      }
      slivers.add(
        SliverToBoxAdapter(
          child: _gutter(
            EpSectionHeader(
              label: 'BANDS',
              action: 'See more',
              actionKey: const Key('feed-toggle-bands'),
              onAction: () => app.go(Screen.exploreCollection, 'bands'),
              padding: const EdgeInsets.only(top: 32, bottom: 4),
            ),
          ),
        ),
      );
      if (bandIds.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: EpCarousel(
              key: const Key('feed-bands'),
              itemExtent: 120,
              height: exploreBandRailHeight(context),
              wrapWhenScaled: true,
              itemCount: bandIds.length,
              itemBuilder: (_, i) {
                final id = bandIds[i];
                return ExploreBandTile(
                  key: Key('explore-band-card-$id'),
                  band: app.band(id)!,
                  width: 120,
                  onTap: () => app.openBand(id),
                );
              },
            ),
          ),
        );
      }
      slivers.add(
        SliverToBoxAdapter(
          child: _gutter(
            Column(
              children: [
                const SizedBox(
                  height: EpLayout.formSectionGap,
                  child: Center(child: EpHairline()),
                ),
                app.authed
                    ? EpMenuRow(
                        key: const Key('feed-find-people'),
                        icon: Icons.group_outlined,
                        label: 'Find people',
                        sub: 'Follow people to see where they are going',
                        onTap: () => app.go(Screen.people),
                      )
                    : EpMenuRow(
                        key: const Key('feed-friends-sign-in'),
                        icon: Icons.group_outlined,
                        label: 'Sign in to see friends',
                        sub: 'See where friends are going',
                        onTap: () =>
                            app.needAuth(const PendingAuth(PendingKind.myGigs)),
                      ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    }
    slivers.add(
      const SliverToBoxAdapter(child: SizedBox(height: tabBarClearance)),
    );
    return slivers;
  }

  Widget _gutter(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
    child: child,
  );
}

class _PinnedGenreRail extends SliverPersistentHeaderDelegate {
  const _PinnedGenreRail({required this.child, required this.extent});
  final Widget child;
  final double extent;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(
    child: OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: extent + 80,
      child: child,
    ),
  );

  @override
  bool shouldRebuild(covariant _PinnedGenreRail oldDelegate) =>
      oldDelegate.extent != extent || oldDelegate.child != child;
}
