import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../explore_ranking.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/discovery_quick_filters.dart';
import '../widgets/ep_carousel.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/explore_friends.dart';
import '../widgets/explore_genres.dart';
import '../widgets/explore_tiles.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/location_eyebrow.dart';

typedef _BrowseBlock = ({Widget widget, bool right});

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final TextEditingController _controller;
  late String _lastSubmittedQuery;
  Timer? _scopeFeedbackTimer;
  bool _showScopeFeedback = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _lastSubmittedQuery = app.query;
    _controller = TextEditingController(text: _lastSubmittedQuery);
    app.ensureSocial();
  }

  @override
  void dispose() {
    _scopeFeedbackTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_lastSubmittedQuery != app.query) {
      _lastSubmittedQuery = app.query;
      _controller.value = TextEditingValue(
        text: app.query,
        selection: TextSelection.collapsed(offset: app.query.length),
      );
    }
    final q = app.query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final modeKey = searching
        ? const ValueKey('explore-results-search')
        : app.exploreGenrePage != null
        ? ValueKey('explore-genre-${app.exploreGenre}')
        : ValueKey('explore-browse-${app.exploreResultType.name}');
    return Stack(
      children: [
        Positioned.fill(
          child: CustomScrollView(
            key: modeKey,
            slivers: _slivers(context, app, searching, q),
          ),
        ),
        if (_showScopeFeedback)
          Positioned(
            top: 0,
            left: EpLayout.gutter,
            right: EpLayout.gutter,
            child: Semantics(
              liveRegion: true,
              label: 'Updating search results',
              child: const LinearProgressIndicator(
                key: Key('explore-scope-progress'),
                minHeight: 2,
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _slivers(
    BuildContext context,
    AppState app,
    bool searching,
    String q,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final baseExtent = (44 + 8 + 52 + 8 + 40 + 12 + 1) * scale;
    final maxHeader = MediaQuery.sizeOf(context).height * .45;
    // At extreme text scales, keep tabs and filters pinned and move the rail into content.
    final pinRail = baseExtent <= maxHeader;
    final extent = pinRail ? baseExtent : (44 + 8 + 52 + 12 + 1) * scale;
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final controls = DecoratedBox(
      decoration: BoxDecoration(color: context.epColors.background),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
            child: SizedBox(
              key: const Key('explore-result-tabs'),
              width: double.infinity,
              child: EpSegmentTabs(
                labels: const ['All', 'Events', 'Bands', 'Venues'],
                selected: ExploreResultType.values.indexOf(
                  app.exploreResultType,
                ),
                onSelect: (i) => _selectScope(app, ExploreResultType.values[i]),
                scrollable: largeText,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
            child: DiscoveryQuickFilters(
              filterButtonKey: const Key('explore-filter-button'),
              badgeKey: const Key('explore-filters-count'),
            ),
          ),
          const SizedBox(height: 8),
          if (pinRail)
            ExploreGenreRail(
              chips: app.exploreGenres,
              selected: app.exploreGenre,
              onSelect: app.setExploreGenre,
            ),
          if (pinRail) const SizedBox(height: 12),
          const EpHairline(),
        ],
      ),
    );
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            EpLayout.gutter,
            MediaQuery.paddingOf(context).top + 22,
            EpLayout.gutter,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EpDisplay('Explore', size: 44),
              const SizedBox(height: 6),
              const DiscoveryLocationEyebrow(
                controlKey: ValueKey('explore-location-control'),
                failureKey: ValueKey('explore-location-failure'),
              ),
              const SizedBox(height: 16),
              EpUnderlineField(
                fieldKey: const Key('explore-search-field'),
                controller: _controller,
                icon: Icons.search,
                hint: 'Bands, venues, gigs…',
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearch(app),
                trailing: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('explore-search-submit'),
                        tooltip: 'Search',
                        onPressed: () => _submitSearch(app),
                        color: context.epColors.muted,
                        icon: const Icon(Icons.arrow_forward, size: 18),
                      ),
                      if (value.text.isNotEmpty || searching)
                        IconButton(
                          key: const Key('explore-search-clear'),
                          tooltip: 'Clear search',
                          onPressed: () => _clearSearch(app),
                          color: context.epColors.muted,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPersistentHeader(
        pinned: true,
        delegate: _PinnedExploreControls(child: controls, extent: extent),
      ),
    ];
    if (!pinRail) {
      slivers.add(
        SliverToBoxAdapter(
          child: ExploreGenreRail(
            chips: app.exploreGenres,
            selected: app.exploreGenre,
            onSelect: app.setExploreGenre,
          ),
        ),
      );
    }
    if (searching) {
      final rows = _SearchResults(app: app, q: q).rows;
      slivers.add(
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) =>
              _SearchResults(app: app, q: q).buildRow(context, rows[i]),
        ),
      );
    } else {
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
        final blocks = _browseBlocks(context, app);
        final left = blocks.where((b) => !b.right).toList();
        final right = blocks.where((b) => b.right).toList();
        if (!EpLayout.isDesktop(context) || left.isEmpty || right.isEmpty) {
          final single = left.isEmpty
              ? right
              : right.isEmpty
              ? left
              : blocks;
          slivers.add(
            SliverList.builder(
              itemCount: single.length,
              itemBuilder: (_, i) => single[i].widget,
            ),
          );
        } else {
          slivers.add(
            SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(children: [for (final b in left) b.widget]),
                  ),
                  const SizedBox(width: 40),
                  Expanded(
                    child: Column(children: [for (final b in right) b.widget]),
                  ),
                ],
              ),
            ),
          );
        }
      }
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

  List<_BrowseBlock> _browseBlocks(BuildContext context, AppState app) {
    final home = app.exploreHome;
    final scope = app.exploreResultType;
    final events =
        scope == ExploreResultType.all || scope == ExploreResultType.events;
    final bands =
        scope == ExploreResultType.all || scope == ExploreResultType.bands;
    final venues =
        scope == ExploreResultType.all || scope == ExploreResultType.venues;
    final recIds = [
      for (final id in home.recommendedBandIds)
        if (app.band(id) != null) id,
    ];
    final directoryIds = [
      for (final id in app.exploreBandIds)
        if (!home.recommendedBandIds.contains(id) && app.band(id) != null) id,
    ].take(12).toList();
    final out = <_BrowseBlock>[];
    final friendsBlock = _gutter(
      ExploreFriendsSection(
        entries: app.friendsGoing,
        signedIn: app.authed,
        hasFriends: app.hasFriends,
        onFindPeople: () => app.go(Screen.people),
        onSignIn: () => app.needAuth(const PendingAuth(PendingKind.myGigs)),
        onOpenGig: app.openGig,
        onSeeAll: () => app.go(Screen.exploreCollection, 'friends'),
        venueLine: (g) => app.venue(g.venueId).name,
      ),
    );
    final friendsEarly = app.hasFriends && app.friendsGoing.isNotEmpty;
    if (bands && recIds.isNotEmpty) {
      out.add((
        widget: _gutter(
          EpSectionHeader(
            label: home.personalised ? 'RECOMMENDED FOR YOU' : 'BANDS TO KNOW',
          ),
        ),
        right: false,
      ));
      out.add((
        widget: EpCarousel(
          key: const Key('explore-recommended'),
          itemExtent: 88,
          height: 136,
          wrapWhenScaled: true,
          semanticsLabel: 'Recommended bands',
          itemCount: recIds.length,
          itemBuilder: (_, i) {
            final id = recIds[i];
            return ExploreBandTile(
              key: Key('explore-recommended-$id'),
              band: app.band(id)!,
              onTap: () => app.openBand(id),
            );
          },
        ),
        right: false,
      ));
    }
    if (events && friendsEarly) {
      out.add((widget: friendsBlock, right: true));
    }
    if (events && home.collections.isNotEmpty) {
      out.add((
        widget: _gutter(EpSectionHeader(label: 'COLLECTIONS')),
        right: false,
      ));
      out.add((
        widget: EpCarousel(
          key: const Key('explore-collections'),
          itemExtent: 160,
          height: 200,
          wrapWhenScaled: true,
          itemCount: home.collections.length,
          itemBuilder: (_, i) {
            final c = home.collections[i];
            return ExploreCollectionCard(
              key: Key('explore-collection-${c.key}'),
              collection: c,
              onTap: () => app.go(Screen.exploreCollection, c.key),
            );
          },
        ),
        right: false,
      ));
    }
    if (events) {
      for (final spec in [
        (home.tonight, 'TONIGHT', 3, 'tonight'),
        (home.week, 'THIS WEEK', 4, 'week'),
      ]) {
        final gigs = spec.$1;
        if (gigs.isEmpty) continue;
        out.add((
          widget: _gutter(
            EpSectionHeader(
              key: Key('explore-events-${spec.$4}'),
              label: '${spec.$2} · ${gigs.length}',
              action: gigs.length > spec.$3 ? 'SEE ALL' : null,
              onAction: () => app.go(Screen.exploreCollection, spec.$4),
            ),
          ),
          right: false,
        ));
        out.addAll(
          gigs
              .take(spec.$3)
              .map(
                (g) => (
                  widget: _gutter(
                    FanEventCard(gig: g, app: app, showDistance: true),
                  ),
                  right: false,
                ),
              ),
        );
      }
    }
    if (events &&
        home.tonight.isEmpty &&
        home.week.isEmpty &&
        home.upcoming.isEmpty) {
      out.add((
        widget: _gutter(
          Text(
            'No nearby events in the loaded feed.',
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
        ),
        right: false,
      ));
    }
    if (venues) {
      final label = scope == ExploreResultType.all
          ? 'VENUES WITH SHOWS · ${home.venues.length}'
          : 'VENUES · ${home.venues.length}';
      out.add((
        widget: _gutter(
          _VenueHeader(
            label: label,
            action: scope == ExploreResultType.all
                ? () => app.go(Screen.exploreCollection, 'venues')
                : null,
          ),
        ),
        right: true,
      ));
      if (home.venues.isEmpty) {
        out.add((widget: _gutter(_buildVenueState(context, app)), right: true));
      } else if (scope == ExploreResultType.venues) {
        out.addAll(
          home.venues.map(
            (e) => (
              widget: _gutter(_VenueRow(venue: e.venue, app: app)),
              right: true,
            ),
          ),
        );
      } else {
        out.add((
          widget: EpCarousel(
            key: const Key('explore-venues'),
            itemExtent: 168,
            height: 120,
            wrapWhenScaled: true,
            itemCount: home.venues.length,
            itemBuilder: (_, i) {
              final e = home.venues[i];
              return ExploreVenueTile(
                key: Key('explore-venue-tile-${e.venue.id}'),
                entry: e,
                distance: app.distanceOf(e.venue),
                onTap: () => app.openVenue(e.venue.id),
              );
            },
          ),
          right: true,
        ));
      }
    }
    if (events && !friendsEarly) {
      out.add((widget: friendsBlock, right: true));
    }
    if (bands) {
      if (directoryIds.isNotEmpty) {
        out.add((
          widget: _gutter(
            EpSectionHeader(
              label: app.hasMoreExploreBands
                  ? 'BANDS'
                  : 'BANDS · ${app.exploreBandIds.length}',
            ),
          ),
          right: true,
        ));
        out.add((
          widget: EpCarousel(
            key: const Key('explore-bands'),
            itemExtent: 88,
            height: 136,
            wrapWhenScaled: true,
            itemCount: directoryIds.length,
            itemBuilder: (_, i) {
              final id = directoryIds[i];
              return ExploreBandTile(
                key: Key('explore-band-card-$id'),
                band: app.band(id)!,
                onTap: () => app.openBand(id),
              );
            },
          ),
          right: true,
        ));
      }
      out.add((
        widget: _gutter(
          EpMenuRow(
            key: const Key('explore-toggle-bands'),
            icon: Icons.groups_outlined,
            label: 'All bands',
            trailingText: app.hasMoreExploreBands
                ? null
                : '${app.exploreBandIds.length}',
            onTap: () => app.go(Screen.exploreCollection, 'bands'),
          ),
        ),
        right: true,
      ));
    }
    if (events && home.upcoming.isNotEmpty) {
      out.add((
        widget: _gutter(
          EpSectionHeader(
            key: const Key('explore-upcoming'),
            label: 'UPCOMING · ${home.upcoming.length}',
            action: home.upcoming.length > 4 ? 'SEE ALL' : null,
            onAction: () => app.go(Screen.exploreCollection, 'upcoming'),
          ),
        ),
        right: false,
      ));
      out.addAll(
        home.upcoming
            .take(4)
            .map(
              (g) => (
                widget: _gutter(
                  FanEventCard(gig: g, app: app, showDistance: true),
                ),
                right: false,
              ),
            ),
      );
    }
    return out;
  }

  Widget _buildVenueState(BuildContext context, AppState app) {
    if (app.venueStatus == DataStatus.connecting) {
      return Text(
        'Loading venues…',
        style: Theme.of(
          context,
        ).textTheme.epBody.copyWith(color: context.epColors.muted),
      );
    }
    if (app.venueStatus == DataStatus.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't load venues.",
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
          const SizedBox(height: 10),
          EpPill(label: 'Retry', onPressed: app.retryVenues),
        ],
      );
    }
    return Text(
      'No venues listed yet.',
      style: Theme.of(
        context,
      ).textTheme.epBody.copyWith(color: context.epColors.muted),
    );
  }

  void _submitSearch(AppState app) {
    final query = _controller.text.trim();
    _lastSubmittedQuery = query;
    if (_controller.text != query) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    app.setQuery(query);
  }

  void _clearSearch(AppState app) {
    _controller.clear();
    _lastSubmittedQuery = '';
    app.setQuery('');
  }

  void _selectScope(AppState app, ExploreResultType type) {
    if (type == app.exploreResultType) return;
    _scopeFeedbackTimer?.cancel();
    setState(() => _showScopeFeedback = true);
    app.setExploreResultType(type);
    _scopeFeedbackTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _showScopeFeedback = false);
    });
  }
}

class _PinnedExploreControls extends SliverPersistentHeaderDelegate {
  const _PinnedExploreControls({required this.child, required this.extent});
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
  bool shouldRebuild(covariant _PinnedExploreControls oldDelegate) =>
      oldDelegate.extent != extent || oldDelegate.child != child;
}

class _VenueHeader extends StatelessWidget {
  const _VenueHeader({required this.label, this.action});
  final String label;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Row(
      children: [
        Expanded(child: EpEyebrow(label)),
        if (action != null)
          TextButton(
            key: const Key('explore-toggle-venues'),
            onPressed: action,
            child: const EpMonoText('SEE ALL'),
          ),
      ],
    ),
  );
}

class _SearchResults extends StatelessWidget {
  final AppState app;
  final String q;
  const _SearchResults({required this.app, required this.q});

  List<_SearchResultRow> get rows {
    final selectedGenre = app.exploreGenre;
    bool gigMatchesGenre(Gig gig) =>
        selectedGenre == null ||
        gig.genres.any((genre) => canonicalGenre(genre) == selectedGenre) ||
        gig.lineup.any(
          (id) =>
              app
                  .band(id)
                  ?.genres
                  .any((g) => canonicalGenre(g) == selectedGenre) ??
              false,
        );
    bool bandMatchesGenre(Band band) =>
        selectedGenre == null ||
        band.genres.any((g) => canonicalGenre(g) == selectedGenre);
    final bandIds = [
      for (final id in app.exploreBandIds)
        if (app.band(id) case final Band band)
          if (bandMatchesGenre(band) &&
              (band.name.toLowerCase().contains(q) ||
                  band.genres.any((genre) => genre.toLowerCase().contains(q))))
            id,
    ];
    final gigs = app.allGigs
        .where(
          (g) =>
              gigMatchesGenre(g) &&
              (g.title.toLowerCase().contains(q) ||
                  app.venue(g.venueId).name.toLowerCase().contains(q) ||
                  g.genres.any((genre) => genre.toLowerCase().contains(q)) ||
                  g.lineup.any(
                    (id) =>
                        app.band(id)?.name.toLowerCase().contains(q) ?? false,
                  )),
        )
        .toList();
    final venues = app.venues
        .where(
          (v) =>
              v.name.toLowerCase().contains(q) ||
              v.area.toLowerCase().contains(q) ||
              v.addr.toLowerCase().contains(q),
        )
        .toList();
    final type = app.exploreResultType;
    final out = <_SearchResultRow>[];
    if (type == ExploreResultType.all || type == ExploreResultType.events) {
      out.add(_SearchSectionRow('Events · ${gigs.length}'));
      if (gigs.isEmpty)
        out.add(
          _SearchMessageRow(
            type == ExploreResultType.events
                ? 'No events found.'
                : 'No gigs found.',
          ),
        );
      else
        out.addAll(gigs.map(_SearchGigRow.new));
    }
    if (type == ExploreResultType.all || type == ExploreResultType.bands) {
      out.add(_SearchSectionRow('Bands · ${bandIds.length}'));
      if (bandIds.isEmpty)
        out.add(const _SearchMessageRow('No bands found.'));
      else
        out.addAll(bandIds.map(_SearchBandRow.new));
    }
    if (type == ExploreResultType.all || type == ExploreResultType.venues) {
      out.add(_SearchSectionRow('Venues · ${venues.length}'));
      if (venues.isEmpty)
        out.add(const _SearchMessageRow('No venues found.'));
      else
        out.addAll(venues.map(_SearchVenueRow.new));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final rows = this.rows;
    return ListView.builder(
      key: const ValueKey('explore-results-search'),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) => index == rows.length
          ? const SizedBox(height: tabBarClearance)
          : buildRow(context, rows[index]),
    );
  }

  Widget buildRow(BuildContext context, _SearchResultRow row) =>
      _gutterRow(context, switch (row) {
        _SearchSectionRow(:final label) => EpSectionHeader(label: label),
        _SearchMessageRow(:final message) => Text(
          message,
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
        _SearchGigRow(:final gig) => KeyedSubtree(
          key: ValueKey('fan-event-${gig.id}'),
          child: _ExploreEventRow(gig: gig, app: app, showActions: true),
        ),
        _SearchBandRow(:final bandId) => ExploreBandRow(
          key: ValueKey('explore-band-card-$bandId'),
          bandId: bandId,
          app: app,
        ),
        _SearchVenueRow(:final venue) => _VenueRow(venue: venue, app: app),
      });

  Widget _gutterRow(BuildContext context, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
    child: child,
  );
}

sealed class _SearchResultRow {
  const _SearchResultRow();
}

class _SearchSectionRow extends _SearchResultRow {
  const _SearchSectionRow(this.label);

  final String label;
}

class _SearchMessageRow extends _SearchResultRow {
  const _SearchMessageRow(this.message);

  final String message;
}

class _SearchGigRow extends _SearchResultRow {
  const _SearchGigRow(this.gig);

  final Gig gig;
}

class _SearchBandRow extends _SearchResultRow {
  const _SearchBandRow(this.bandId);

  final String bandId;
}

class _SearchVenueRow extends _SearchResultRow {
  const _SearchVenueRow(this.venue);

  final Venue venue;
}

class _ExploreEventRow extends StatelessWidget {
  const _ExploreEventRow({
    required this.gig,
    required this.app,
    this.showActions = false,
  });

  final Gig gig;
  final AppState app;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    return EpGigRow(
      key: ValueKey('explore-event-${gig.id}'),
      date: gig.startsAt,
      title: gig.title,
      meta: showActions
          ? [
              if (app.isDiscoveryBoosted(gig))
                'Discovery boost · Complete listing',
              '${gig.dateShort} · Doors ${gig.doorsLabel}',
              for (final bandId in gig.lineup)
                if (app.band(bandId) case final Band band) band.name,
              gig.ageRequirement.label,
              if (gig.lifecycle == GigLifecycle.cancelled) 'Cancelled',
            ].join(' · ')
          : null,
      sub: [
        venue.name,
        app.distanceOf(venue),
        gig.priceLabel,
        '${app.rsvpCount(gig)} going',
      ].where((part) => part.isNotEmpty).join(' · '),
      trailing: showActions ? _SearchEventActions(gig: gig, app: app) : null,
      onTap: () => app.openGig(gig.id),
    );
  }
}

/// Search previously exposed these actions on its event cards. Keep them one
/// tap away without crowding the date, title and venue in the shared gig row.
class _SearchEventActions extends StatelessWidget {
  const _SearchEventActions({required this.gig, required this.app});

  final Gig gig;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final saved = app.saved.contains(gig.id);
    final external = gig.tix == Ticketing.external;
    final going = app.rsvps.contains(gig.id);
    return PopupMenuButton<VoidCallback>(
      key: ValueKey('event-actions-${gig.id}'),
      tooltip: 'Event actions',
      color: context.epColors.panel,
      shape: const RoundedRectangleBorder(),
      icon: Icon(Icons.more_horiz, size: 18, color: context.epColors.muted),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          key: ValueKey('save-${gig.id}'),
          value: () => app.requestSave(gig.id),
          child: EpMonoText(saved ? 'Remove saved event' : 'Save event'),
        ),
        PopupMenuItem(
          key: ValueKey('share-${gig.id}'),
          value: () => copyForUser(
            context,
            publicWebUrl('g/${gig.publicRef}'),
            successMessage:
                'Link copied: ${publicWebDisplayUrl('g/${gig.publicRef}')}',
          ),
          child: const EpMonoText('Share event'),
        ),
        if (gig.lifecycle != GigLifecycle.cancelled)
          PopupMenuItem(
            key: ValueKey('ticket-action-${gig.id}'),
            value: () {
              if (external) {
                final url = gig.externalUrl;
                if (url == null || url.isEmpty) {
                  app.say('No ticket link listed for this gig.');
                } else {
                  openExternalForUser(context, url);
                }
              } else if (going) {
                app.toggleRsvp(gig.id);
              } else {
                app.requestRsvp(gig.id);
              }
            },
            child: EpMonoText(
              external
                  ? 'Tickets ↗'
                  : going
                  ? 'Going ✓'
                  : 'RSVP',
            ),
          ),
      ],
    );
  }
}

class _VenueRow extends StatelessWidget {
  const _VenueRow({required this.venue, required this.app});

  final Venue venue;
  final AppState app;

  @override
  Widget build(BuildContext context) => EpEntityRow(
    title: venue.name,
    sub: [venue.area, venue.addr].where((part) => part.isNotEmpty).join(', '),
    // EpEntityRow accepts a string title, so verification sits beside the
    // title in the trailing column, with distance immediately below it.
    trailing: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (venue.verified) ...[
          EpBadge(
            key: Key('explore-venue-verified-${venue.id}'),
            label: 'Verified',
            variant: EpBadgeVariant.outline,
          ),
          const SizedBox(height: 4),
        ],
        EpMonoText(app.distanceOf(venue), color: context.epColors.muted),
      ],
    ),
    onTap: () => app.openVenue(venue.id),
  );
}
