import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/discovery_filters_sheet.dart';
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
              Text('Explore', style: Theme.of(context).textTheme.epPageHeading),
              const SizedBox(height: 10),
              TextField(
                key: const Key('explore-search-field'),
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submitSearch(app),
                style: Theme.of(context).textTheme.epBody,
                decoration: epInputDecoration('Bands, venues, gigs…').copyWith(
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
        _SearchTypeTabs(app: app),
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
                  onOpenFilters: () => showDiscoveryFiltersSheet(context),
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

    return ListView.builder(
      key: ValueKey('explore-results-${type.name}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
      itemCount: resultBuilders.length,
      itemBuilder: (context, index) => resultBuilders[index](context),
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
            ).textTheme.epLabel.copyWith(fontSize: 11, letterSpacing: .4),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? Ep.volt : Ep.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Ep.dark
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
      key: ValueKey('explore-band-card-$bandId'),
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
                  [band.genreLine, '${band.followersLabel} fans'].join(' · '),
                  style: Theme.of(context).textTheme.epCaption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: ValueKey('explore-follow-$bandId'),
            onPressed: () => app.requestFollow(bandId),
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(48, 48)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            child: Text(
              app.follows.contains(bandId) ? 'FOLLOWING ✓' : 'FOLLOW',
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
  final VoidCallback onOpenFilters;

  const _BrowseRows({
    required this.app,
    required this.showAllBands,
    required this.showAllVenues,
    required this.onSearch,
    required this.onToggleBands,
    required this.onToggleVenues,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    final gigs = app.allGigs;
    final previewBandIds = app.exploreBandIds.take(3).toList();
    final tonight = gigs.where((gig) => gig.when == GigWhen.tonight).toList();
    final tonightIds = tonight.map((gig) => gig.id).toSet();
    final free = gigs
        .where(
          (gig) =>
              gig.free &&
              gig.when != GigWhen.later &&
              !tonightIds.contains(gig.id),
        )
        .toList();
    final type = app.exploreResultType;
    final showEvents =
        type == ExploreResultType.all || type == ExploreResultType.events;
    final showBands =
        type == ExploreResultType.all || type == ExploreResultType.bands;
    final showVenues =
        type == ExploreResultType.all || type == ExploreResultType.venues;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, tabBarClearance),
      children: [
        const SectionLabel('GENRES'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final genre in const ['punk', 'garage', 'noise'])
              EpChip(label: genre, active: false, onTap: () => onSearch(genre)),
            EpChip(
              label: '+ FILTERS',
              active: false,
              ghost: true,
              onTap: onOpenFilters,
            ),
          ],
        ),
        if (showEvents) ...[
          if (tonight.isNotEmpty) ...[
            SectionBar(label: 'TONIGHT NEAR YOU', count: tonight.length),
            _EventRows(gigs: tonight, app: app),
          ],
          if (free.isNotEmpty) ...[
            SectionBar(label: 'FREE THIS WEEK', count: free.length),
            _EventRows(gigs: free, app: app),
          ],
          if (tonight.isEmpty && free.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(
                'No nearby events in the loaded feed.',
                style: Theme.of(context).textTheme.epCaption,
              ),
            ),
        ],
        if (showBands) ...[
          _SectionHeading(
            label: 'BANDS ON EARPLUG',
            actionLabel: showAllBands ? 'SEE LESS BANDS' : 'SEE ALL BANDS',
            actionKey: const Key('explore-toggle-bands'),
            onAction: onToggleBands,
          ),
          const SizedBox(height: 8),
          Column(
            key: showAllBands
                ? const Key('explore-all-bands')
                : const Key('explore-band-preview'),
            children: [
              for (final bandId
                  in showAllBands ? app.exploreBandIds : previewBandIds) ...[
                _BandRow(bandId: bandId, app: app),
                const SizedBox(height: 7),
              ],
              if (showAllBands) _BandPageStatus(app: app),
            ],
          ),
        ],
        if (showVenues) ...[
          const SizedBox(height: 10),
          _VenueRows(
            app: app,
            showAll: showAllVenues,
            onToggle: onToggleVenues,
          ),
        ],
      ],
    );
  }
}

class _EventRows extends StatelessWidget {
  const _EventRows({required this.gigs, required this.app});

  final List<Gig> gigs;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final gig in gigs) ...[
          _ExploreEventRow(gig: gig, app: app),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ExploreEventRow extends StatelessWidget {
  const _ExploreEventRow({required this.gig, required this.app});

  final Gig gig;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    return EpCard(
      key: ValueKey('explore-event-${gig.id}'),
      padding: const EdgeInsets.all(10),
      onTap: () => app.openGig(gig.id),
      child: Row(
        children: [
          DateBlock(
            day: gig.startsAt.day.toString().padLeft(2, '0'),
            month: monthNamesUpper[gig.startsAt.month - 1],
            semanticLabel: gig.dateShort,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gig.title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.epLabel,
                ),
                const SizedBox(height: 3),
                Text(
                  [venue.name, app.distanceOf(venue)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.epCaption,
                ),
                const SizedBox(height: 2),
                Text(
                  '${gig.priceLabel} · ${gig.going} going',
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
        TextButton(
          key: actionKey,
          onPressed: onAction,
          child: Text(
            actionLabel,
            maxLines: 2,
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.epLabel.copyWith(fontSize: 11, letterSpacing: .7),
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
