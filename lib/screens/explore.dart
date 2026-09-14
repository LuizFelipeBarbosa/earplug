import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_links.dart';
import '../app_state.dart';
import '../explore_ranking.dart';
import '../models.dart';
import '../services/user_actions.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_carousel.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/explore_friends.dart';
import '../widgets/explore_genres.dart';
import '../widgets/explore_tiles.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final TextEditingController _controller;
  late String _lastSubmittedQuery;

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
        : const ValueKey('explore-browse-all');
    return CustomScrollView(
      key: modeKey,
      slivers: _slivers(context, app, searching, q),
    );
  }

  List<Widget> _slivers(
    BuildContext context,
    AppState app,
    bool searching,
    String q,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final baseExtent = (40 + 12 + 1) * scale;
    final maxHeader = MediaQuery.sizeOf(context).height * .45;
    final pinRail = baseExtent <= maxHeader;
    final extent = pinRail ? baseExtent : 1 * scale;
    final controls = DecoratedBox(
      decoration: BoxDecoration(color: context.epColors.background),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pinRail) ...[
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
              const SizedBox(height: 16),
              EpUnderlineField(
                fieldKey: const Key('explore-search-field'),
                controller: _controller,
                icon: Icons.search,
                hint: 'Events, venues, bands, places…',
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
      final results = _SearchResults(app: app, q: q);
      final rows = results.rows;
      slivers.add(
        SliverList.builder(
          itemCount: rows.length,
          itemBuilder: (context, i) => results.buildRow(context, rows[i]),
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
                    key: const Key('explore-featured'),
                    itemExtent: extent,
                    height: height,
                    wrapWhenScaled: true,
                    itemCount: home.featured.length,
                    itemBuilder: (_, i) {
                      final gig = home.featured[i];
                      return ExploreFeaturedCard(
                        key: Key('explore-featured-${gig.id}'),
                        gig: gig,
                        venueName: app.venue(gig.venueId).name,
                        onTap: () => app.openGig(gig.id),
                        width: extent,
                        height: height,
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
                  ExploreEventRow(
                    key: Key('explore-for-you-${gig.id}'),
                    gig: gig,
                    venueName: app.venue(gig.venueId).name,
                    lineup: exploreLineupFor(gig, app),
                    onTap: () => app.openGig(gig.id),
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
                  key: const Key('explore-empty'),
                  style: Theme.of(
                    context,
                  ).textTheme.epBody.copyWith(color: context.epColors.muted),
                ),
              ),
            ),
          );
        }
        slivers.add(
          SliverToBoxAdapter(
            child: _gutter(
              ExploreFriendsSection(
                entries: app.friendsGoing,
                signedIn: app.authed,
                hasFriends: app.hasFriends,
                onFindPeople: () => app.go(Screen.people),
                onSignIn: () =>
                    app.needAuth(const PendingAuth(PendingKind.myGigs)),
                onOpenGig: app.openGig,
                onSeeAll: () => app.go(Screen.exploreCollection, 'friends'),
                venueLine: (g) => app.venue(g.venueId).name,
                previewCount: 3,
                title: 'People you know are attending',
              ),
            ),
          ),
        );
        slivers.add(
          SliverToBoxAdapter(
            child: _gutter(EpSectionHeader(label: 'EXPLORE VENUES & BANDS')),
          ),
        );
        if (home.discover.isNotEmpty) {
          slivers.add(
            SliverToBoxAdapter(
              child: EpCarousel(
                key: const Key('explore-discover'),
                itemExtent: 168,
                height: 132,
                wrapWhenScaled: true,
                itemCount: home.discover.length,
                itemBuilder: (_, i) {
                  final entry = home.discover[i];
                  if (entry.kind == DiscoverKind.venue) {
                    final venue = entry.venue!;
                    return ExploreVenueTile(
                      key: Key('explore-venue-tile-${venue.venue.id}'),
                      entry: venue,
                      distance: app.distanceOf(venue.venue),
                      onTap: () => app.openVenue(venue.venue.id),
                    );
                  }
                  final band = entry.bandId == null
                      ? null
                      : app.band(entry.bandId!);
                  if (band == null) return const SizedBox.shrink();
                  return SizedBox(
                    width: 168,
                    child: Center(
                      child: ExploreBandTile(
                        key: Key('explore-band-card-${entry.bandId}'),
                        band: band,
                        onTap: () => app.openBand(entry.bandId!),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        }
        slivers.add(
          SliverToBoxAdapter(
            child: _gutter(
              EpMenuRow(
                key: const Key('explore-toggle-bands'),
                icon: Icons.groups_outlined,
                label: 'All bands',
                onTap: () => app.go(Screen.exploreCollection, 'bands'),
              ),
            ),
          ),
        );
        slivers.add(
          SliverToBoxAdapter(
            child: _gutter(
              EpMenuRow(
                key: const Key('explore-toggle-venues'),
                icon: Icons.place_outlined,
                label: 'All venues',
                onTap: () => app.go(Screen.exploreCollection, 'venues'),
              ),
            ),
          ),
        );
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
              v.addr.toLowerCase().contains(q) ||
              (v.neighborhood?.toLowerCase().contains(q) ?? false) ||
              (v.city?.toLowerCase().contains(q) ?? false),
        )
        .toList();
    final locations = <_LocationMatch>[];
    final seenLocations = <String>{};
    for (final city in FanCity.values) {
      if (city.label.toLowerCase().contains(q) &&
          seenLocations.add(city.label.toLowerCase())) {
        locations.add(_LocationMatch(label: city.label, city: city));
      }
    }
    for (final venue in app.venues) {
      for (final value in [venue.neighborhood, venue.city]) {
        final label = value?.trim() ?? '';
        final normalized = label.toLowerCase();
        if (label.isNotEmpty &&
            normalized.contains(q) &&
            seenLocations.add(normalized)) {
          locations.add(_LocationMatch(label: label));
        }
      }
    }
    final out = <_SearchResultRow>[];
    if (locations.isNotEmpty) {
      out.add(_SearchSectionRow('LOCATIONS · ${locations.length}'));
      out.addAll(locations.map(_SearchLocationRow.new));
    }
    if (gigs.isNotEmpty) {
      out.add(_SearchSectionRow('EVENTS · ${gigs.length}'));
      out.addAll(gigs.map(_SearchGigRow.new));
    }
    if (bandIds.isNotEmpty) {
      out.add(_SearchSectionRow('BANDS · ${bandIds.length}'));
      out.addAll(bandIds.map(_SearchBandRow.new));
    }
    if (venues.isNotEmpty) {
      out.add(_SearchSectionRow('VENUES · ${venues.length}'));
      out.addAll(venues.map(_SearchVenueRow.new));
    }
    if (out.isEmpty) {
      out.add(const _SearchMessageRow('No results.'));
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
        _SearchLocationRow(:final location) => ExploreLocationRow(
          key: Key('explore-location-${_locationSlug(location)}'),
          label: location.label,
          onTap: () {
            if (location.city case final city?) {
              app.setCity(city.name);
              app.setQuery('');
            } else {
              app.setQuery(location.label);
            }
          },
        ),
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

class _SearchLocationRow extends _SearchResultRow {
  const _SearchLocationRow(this.location);

  final _LocationMatch location;
}

class _LocationMatch {
  const _LocationMatch({required this.label, this.city});

  final String label;
  final FanCity? city;
}

String _locationSlug(_LocationMatch location) =>
    location.city?.name ??
    location.label
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

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
