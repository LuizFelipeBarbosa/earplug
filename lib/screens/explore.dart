import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/fan_event_card.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final TextEditingController _controller;
  late String _lastSubmittedQuery;
  bool _showAllBands = false;
  bool _showAllVenues = false;

  @override
  void initState() {
    super.initState();
    _lastSubmittedQuery = context.read<AppState>().query;
    _controller = TextEditingController(text: _lastSubmittedQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Keep programmatic query changes in sync without discarding a draft when
    // unrelated AppState notifications rebuild this screen.
    if (_lastSubmittedQuery != app.query) {
      _lastSubmittedQuery = app.query;
      _controller.value = TextEditingValue(
        text: app.query,
        selection: TextSelection.collapsed(offset: app.query.length),
      );
    }
    final q = app.query.trim().toLowerCase();
    final searching = q.isNotEmpty;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 12),
          decoration: const BoxDecoration(
            color: Ep.background,
            border: Border(bottom: BorderSide(color: Ep.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SEARCH & EXPLORE',
                style: Theme.of(context).textTheme.epPageHeading,
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('explore-search-field'),
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitSearch(app),
                style: Theme.of(context).textTheme.epBody,
                decoration: epInputDecoration('Bands, gigs, venues…').copyWith(
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('explore-search-submit'),
                        tooltip: 'Search',
                        onPressed: () => _submitSearch(app),
                        icon: const Icon(Icons.search),
                      ),
                      if (_controller.text.isNotEmpty || searching)
                        IconButton(
                          key: const Key('explore-search-clear'),
                          tooltip: 'Clear search',
                          onPressed: () => _clearSearch(app),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: searching
              ? _SearchResults(app: app, q: q)
              : _BrowseRows(
                  app: app,
                  showAllBands: _showAllBands,
                  showAllVenues: _showAllVenues,
                  onSearch: (query) {
                    _controller.value = TextEditingValue(
                      text: query,
                      selection: TextSelection.collapsed(offset: query.length),
                    );
                    _submitSearch(app);
                  },
                  onToggleBands: () {
                    setState(() => _showAllBands = !_showAllBands);
                  },
                  onToggleVenues: () {
                    setState(() => _showAllVenues = !_showAllVenues);
                  },
                ),
        ),
      ],
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
}

class _SearchResults extends StatelessWidget {
  final AppState app;
  final String q;

  const _SearchResults({required this.app, required this.q});

  @override
  Widget build(BuildContext context) {
    final bandIds = [
      for (final id in app.exploreBandIds)
        if (app.band(id) case final Band band)
          if (band.name.toLowerCase().contains(q) ||
              band.genres.any((genre) => genre.toLowerCase().contains(q)))
            id,
    ];
    final gigs = app.allGigs.where((g) {
      return g.title.toLowerCase().contains(q) ||
          app.venue(g.venueId).name.toLowerCase().contains(q) ||
          g.genres.any((genre) => genre.toLowerCase().contains(q)) ||
          g.lineup.any(
            (bandId) =>
                app.band(bandId)?.name.toLowerCase().contains(q) ?? false,
          );
    }).toList();
    final venues = app.venues.where((venue) {
      return venue.name.toLowerCase().contains(q) ||
          venue.area.toLowerCase().contains(q) ||
          venue.addr.toLowerCase().contains(q);
    }).toList();

    final type = app.exploreResultType;
    final showEvents =
        type == ExploreResultType.all || type == ExploreResultType.events;
    final showBands =
        type == ExploreResultType.all || type == ExploreResultType.bands;
    final showVenues =
        type == ExploreResultType.all || type == ExploreResultType.venues;
    final resultBuilders = <WidgetBuilder>[];

    if (showEvents) {
      resultBuilders.add(
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: SectionLabel('EVENTS'),
        ),
      );
      if (gigs.isEmpty) {
        resultBuilders.add(
          (context) => Text(
            type == ExploreResultType.events
                ? 'No events found.'
                : 'No gigs found.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        );
      } else {
        for (final gig in gigs) {
          resultBuilders.add(
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FanEventCard(gig: gig, app: app),
            ),
          );
        }
      }
      if (type == ExploreResultType.all) {
        resultBuilders.add((_) => const SizedBox(height: 8));
      }
    }

    if (showBands) {
      resultBuilders.add(
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: SectionLabel('BANDS'),
        ),
      );
      if (bandIds.isEmpty) {
        resultBuilders.add(
          (context) => Text(
            'No bands found.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        );
      } else {
        for (final id in bandIds) {
          resultBuilders.add(
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _BandRow(bandId: id, app: app),
            ),
          );
        }
      }
      if (type == ExploreResultType.all) {
        resultBuilders.add((_) => const SizedBox(height: 8));
      }
    }

    if (showVenues) {
      resultBuilders.add(
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: SectionLabel('VENUES'),
        ),
      );
      if (venues.isEmpty) {
        resultBuilders.add(
          (context) => Text(
            'No venues found.',
            style: Theme.of(context).textTheme.epCaption,
          ),
        );
      } else {
        for (final venue in venues) {
          resultBuilders.add(
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _VenueRow(venue: venue, app: app),
            ),
          );
        }
      }
    }

    return Column(
      children: [
        _SearchTypeTabs(app: app),
        Expanded(
          child: ListView.builder(
            key: ValueKey('explore-results-${type.name}'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
            itemCount: resultBuilders.length,
            itemBuilder: (context, index) => resultBuilders[index](context),
          ),
        ),
      ],
    );
  }
}

class _SearchTypeTabs extends StatelessWidget {
  const _SearchTypeTabs({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    const labels = {
      ExploreResultType.all: 'All',
      ExploreResultType.events: 'Events',
      ExploreResultType.bands: 'Bands',
      ExploreResultType.venues: 'Venues',
    };
    return Container(
      key: const Key('explore-result-tabs'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Ep.border)),
      ),
      child: SegmentedButton<ExploreResultType>(
        segments: [
          for (final entry in labels.entries)
            ButtonSegment(
              value: entry.key,
              label: Text(
                entry.value,
                key: ValueKey('explore-tab-${entry.key.name}'),
              ),
            ),
        ],
        selected: {app.exploreResultType},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          app.setExploreResultType(selection.single);
        },
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 6),
          ),
          textStyle: WidgetStatePropertyAll(
            Theme.of(
              context,
            ).textTheme.epLabel.copyWith(fontSize: 10, letterSpacing: .4),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Ep.surfaceSelected
                : Ep.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Ep.contentPrimary
                : Ep.contentSecondary,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: Ep.border)),
        ),
      ),
    );
  }
}

class _BandRow extends StatelessWidget {
  final String bandId;
  final AppState app;

  const _BandRow({required this.bandId, required this.app});

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: () => app.openBand(bandId),
      child: Row(
        children: [
          BandAvatar(band, size: 36, radius: 8, fontSize: 12),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  band.name.toUpperCase(),
                  style: Theme.of(context).textTheme.epLabel,
                ),
                Text(
                  band.genreLine,
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseRows extends StatelessWidget {
  final AppState app;
  final bool showAllBands;
  final bool showAllVenues;
  final ValueChanged<String> onSearch;
  final VoidCallback onToggleBands;
  final VoidCallback onToggleVenues;

  const _BrowseRows({
    required this.app,
    required this.showAllBands,
    required this.showAllVenues,
    required this.onSearch,
    required this.onToggleBands,
    required this.onToggleVenues,
  });

  @override
  Widget build(BuildContext context) {
    final gigs = app.allGigs;
    final tonight = [
      ...gigs.where((g) => g.when == GigWhen.tonight),
      ...gigs.where((g) => g.when == GigWhen.week).take(3),
    ];
    final free = gigs.where((g) => g.free && g.when != GigWhen.later).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, tabBarClearance),
      children: [
        const SectionLabel('GENRES'),
        const SizedBox(height: 8),
        SizedBox(
          height:
              48 +
              12 * (MediaQuery.textScalerOf(context).scale(1).clamp(1, 2) - 1),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kGenres.length,
            separatorBuilder: (_, _) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              final genre = kGenres[index];
              return EpChip(
                label: genre,
                active: false,
                onTap: () => onSearch(genre),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        const SectionLabel('TONIGHT NEAR YOU', blue: true),
        const SizedBox(height: 8),
        _FlyerRail(gigs: tonight, app: app),
        const SizedBox(height: 18),
        const SectionLabel('FREE THIS WEEK', blue: true),
        const SizedBox(height: 8),
        _FlyerRail(gigs: free, app: app, freeTag: true),
        const SizedBox(height: 18),
        _SectionHeading(
          label: 'BANDS ON EARPLUG',
          actionLabel: showAllBands ? 'SEE LESS BANDS' : 'SEE ALL BANDS',
          actionKey: const Key('explore-toggle-bands'),
          onAction: onToggleBands,
        ),
        const SizedBox(height: 8),
        if (showAllBands)
          Column(
            children: [
              GridView.builder(
                key: const Key('explore-all-bands'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: app.exploreBandIds.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent:
                      126 +
                      40 *
                          (MediaQuery.textScalerOf(
                                context,
                              ).scale(1).clamp(1, 2) -
                              1),
                ),
                itemBuilder: (context, index) => _BandTile(
                  bandId: app.exploreBandIds[index],
                  app: app,
                  width: double.infinity,
                ),
              ),
              const SizedBox(height: 8),
              _BandPageStatus(app: app),
            ],
          )
        else
          SizedBox(
            key: const Key('explore-band-preview'),
            height:
                126 +
                40 *
                    (MediaQuery.textScalerOf(context).scale(1).clamp(1, 2) - 1),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final id in app.exploreBandIds.take(4))
                  _BandTile(bandId: id, app: app),
              ],
            ),
          ),
        const SizedBox(height: 18),
        _VenueRows(app: app, showAll: showAllVenues, onToggle: onToggleVenues),
      ],
    );
  }
}

class _BandPageStatus extends StatelessWidget {
  const _BandPageStatus({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    if (app.exploreBandsLoading) {
      return Text(
        'Loading bands…',
        key: const Key('explore-bands-loading'),
        style: Theme.of(context).textTheme.epCaption,
      );
    }
    if (app.exploreBandsError != null) {
      return Column(
        children: [
          Text(
            "Couldn't load more bands.",
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 7),
          TextButton(
            key: const Key('explore-bands-retry'),
            onPressed: app.retryExploreBands,
            child: const Text('RETRY'),
          ),
        ],
      );
    }
    if (app.hasMoreExploreBands) {
      return TextButton(
        key: const Key('explore-bands-load-more'),
        onPressed: app.loadMoreExploreBands,
        child: const Text('LOAD MORE BANDS'),
      );
    }
    return Text(
      'All bands loaded.',
      key: const Key('explore-bands-end'),
      style: Theme.of(context).textTheme.epCaption,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.label,
    required this.actionLabel,
    required this.actionKey,
    required this.onAction,
  });

  final String label;
  final String actionLabel;
  final Key actionKey;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: SectionLabel(label)),
        Flexible(
          child: TextButton(
            key: actionKey,
            onPressed: onAction,
            child: Text(
              actionLabel,
              maxLines: 2,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.epLabel.copyWith(fontSize: 10, letterSpacing: .7),
            ),
          ),
        ),
      ],
    );
  }
}

class _VenueRows extends StatelessWidget {
  const _VenueRows({
    required this.app,
    required this.showAll,
    required this.onToggle,
  });

  final AppState app;
  final bool showAll;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final venues = app.venues;
    final visibleVenues = showAll ? venues : venues.take(3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(
          label: 'VENUES',
          actionLabel: showAll ? 'SEE LESS VENUES' : 'SEE ALL VENUES',
          actionKey: const Key('explore-toggle-venues'),
          onAction: onToggle,
        ),
        const SizedBox(height: 8),
        if (venues.isNotEmpty)
          for (final venue in visibleVenues) ...[
            _VenueRow(venue: venue, app: app),
            const SizedBox(height: 6),
          ]
        else if (app.venueStatus == DataStatus.connecting)
          Text('Loading venues…', style: Theme.of(context).textTheme.epCaption)
        else if (app.venueStatus == DataStatus.error) ...[
          Text(
            "Couldn't load venues.",
            style: Theme.of(context).textTheme.epCaption,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 120,
            child: EpButton(
              'RETRY',
              kind: EpButtonKind.outline,
              padding: const EdgeInsets.symmetric(vertical: 10),
              onTap: app.retryVenues,
            ),
          ),
        ] else
          Text(
            'No venues listed yet.',
            style: Theme.of(context).textTheme.epCaption,
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
  Widget build(BuildContext context) {
    return EpCard(
      padding: const EdgeInsets.all(9),
      onTap: () => app.openVenue(venue.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  venue.name.toUpperCase(),
                  style: Theme.of(context).textTheme.epLabel,
                ),
                Text(
                  '${venue.addr} · ${venue.area}',
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            app.distanceOf(venue),
            style: Theme.of(context).textTheme.epCaption,
          ),
        ],
      ),
    );
  }
}

class _FlyerRail extends StatelessWidget {
  final List<Gig> gigs;
  final AppState app;
  final bool freeTag;

  const _FlyerRail({
    required this.gigs,
    required this.app,
    this.freeTag = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          186 +
          36 * (MediaQuery.textScalerOf(context).scale(1).clamp(1, 2) - 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          for (final g in gigs)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 134,
                child: EpCard(
                  variant: EpCardVariant.raised,
                  padding: const EdgeInsets.all(8),
                  onTap: () => app.openGig(g.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GigFlyer(
                            g,
                            app.flyer(g.flyKey),
                            width: 118,
                            height: 130,
                            radius: 8,
                            padding: const EdgeInsets.all(10),
                            child: MediaQuery.withNoTextScaling(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    g.title.toUpperCase(),
                                    maxLines: 5,
                                    overflow: TextOverflow.ellipsis,
                                    style: epDisplay(
                                      size: 12,
                                      color: app.flyer(g.flyKey).fg,
                                      height: 1.1,
                                    ),
                                  ),
                                  Text(
                                    g.dateShort,
                                    style: epText(
                                      size: 9,
                                      weight: FontWeight.w800,
                                      letterSpacing: .5,
                                      color: app
                                          .flyer(g.flyKey)
                                          .fg
                                          .withValues(alpha: .85),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (freeTag)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Ep.brand,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  'FREE',
                                  style: Theme.of(context).textTheme.epCaption
                                      .copyWith(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .8,
                                        color: Colors.white,
                                      ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        app.venue(g.venueId).name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epCaption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BandTile extends StatelessWidget {
  final String bandId;
  final AppState app;
  final double width;

  const _BandTile({required this.bandId, required this.app, this.width = 100});

  @override
  Widget build(BuildContext context) {
    final band = app.band(bandId);
    if (band == null) return const SizedBox.shrink();
    return SizedBox(
      width: width,
      child: EpCard(
        variant: EpCardVariant.raised,
        padding: const EdgeInsets.all(6),
        onTap: () => app.openBand(bandId),
        child: Column(
          children: [
            BandAvatar(band, size: 56, radius: 12, fontSize: 18),
            const SizedBox(height: 5),
            Text(
              band.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.epLabel.copyWith(fontSize: 10.5, height: 1.2),
            ),
            const SizedBox(height: 2),
            if (band.genres.isNotEmpty)
              Text(
                band.genres.first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.epCaption.copyWith(fontSize: 9.5),
              ),
          ],
        ),
      ),
    );
  }
}
