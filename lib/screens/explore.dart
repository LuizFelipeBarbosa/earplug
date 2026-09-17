import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../search_query.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_carousel.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_search_field.dart';
import '../widgets/ep_text.dart';
import '../widgets/explore_tiles.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/feed_spacing.dart';

/// The most bands the Explore rail shows: recommendations first, then the
/// directory fills the remaining slots.
const _bandRailLimit = 16;

/// Gap between compact band tiles; tighter than the feed rails' 12.
const _bandRailGap = 8.0;

/// Space between the search field and the first body section. The BANDS rail
/// skips it: its header row is already 44 tall (the See-all target), which
/// centres the eyebrow 15px below the field on its own.
const _bodyTopInset = 12.0;

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late final TextEditingController _controller;
  late String _lastQuery;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _lastQuery = app.query;
    _controller = TextEditingController(text: _lastQuery);
    app.ensureSocial();
    // The directory fetch notifies synchronously, so ask after the first
    // frame, as the bands collection does.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) app.ensureExploreBands();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateQuery(AppState app, String text) {
    _lastQuery = text;
    app.setQuery(text);
  }

  void _runSearch(AppState app, String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _updateQuery(app, text);
    app.recordSearch(text);
  }

  void _clearSearch(AppState app) {
    _controller.clear();
    _updateQuery(app, '');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_lastQuery != app.query) {
      _lastQuery = app.query;
      _controller.value = TextEditingValue(
        text: app.query,
        selection: TextSelection.collapsed(offset: app.query.length),
      );
    }
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              EpLayout.gutter,
              EpLayout.isDesktop(context) ? 0 : 22,
              EpLayout.gutter,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EpDisplay('Explore', size: 44),
                const SizedBox(height: 16),
                EpSearchField(
                  fieldKey: const Key('explore-search-field'),
                  clearKey: const Key('explore-search-clear'),
                  controller: _controller,
                  hint: 'Events, bands, venues, places, tonight, free…',
                  onChanged: (text) => _updateQuery(app, text),
                  onSubmitted: app.recordSearch,
                  onClear: () => _clearSearch(app),
                ),
              ],
            ),
          ),
          Expanded(
            child: app.query.trim().isEmpty
                ? _defaultBody(context, app)
                : _resultsBody(context, app),
          ),
        ],
      ),
    );
  }

  /// Recommended bands first, then the directory, without repeats.
  List<String> _bandRailIds(AppState app) {
    final ids = <String>[];
    for (final id in [
      ...app.exploreHome.recommendedBandIds,
      ...app.exploreBandIds,
    ]) {
      if (!ids.contains(id) && app.band(id) != null) ids.add(id);
      if (ids.length == _bandRailLimit) break;
    }
    return ids;
  }

  Widget _defaultBody(BuildContext context, AppState app) {
    final recents = app.recentSearches;
    final bandIds = _bandRailIds(app);
    return ListView(
      key: const ValueKey('explore-default'),
      padding: EdgeInsets.only(top: bandIds.isEmpty ? _bodyTopInset : 0),
      children: [
        if (bandIds.isNotEmpty) ...[
          epGutter(
            EpSectionHeader(
              label: 'BANDS',
              action: 'See all',
              actionKey: const Key('explore-bands-see-all'),
              onAction: () => app.go(Screen.exploreCollection, 'bands'),
              padding: EdgeInsets.zero,
            ),
          ),
          EpCarousel(
            key: const Key('explore-bands'),
            itemExtent: exploreCompactBandTileWidth,
            height: exploreCompactBandRailHeight(context),
            gap: _bandRailGap,
            wrapWhenScaled: true,
            itemCount: bandIds.length,
            itemBuilder: (_, i) {
              final id = bandIds[i];
              return ExploreBandTile.compact(
                key: Key('explore-band-$id'),
                band: app.band(id)!,
                onTap: () => app.openBand(id),
              );
            },
          ),
        ],
        if (recents.isNotEmpty) ...[
          epGutter(
            const EpSectionHeader(
              label: 'RECENT SEARCHES',
              padding: EdgeInsets.only(top: 24),
            ),
          ),
          for (var i = 0; i < recents.length; i++)
            epGutter(
              EpMenuRow(
                key: Key('explore-recent-$i'),
                icon: Icons.history,
                label: recents[i],
                padding: EdgeInsets.zero,
                trailing: IconButton(
                  key: Key('explore-recent-clear-$i'),
                  tooltip: 'Remove',
                  onPressed: () => app.removeRecentSearch(recents[i]),
                  icon: const Icon(Icons.close, size: 18),
                  color: context.epColors.muted,
                ),
                onTap: () => _runSearch(app, recents[i]),
              ),
            ),
        ],
        epGutter(
          const EpSectionHeader(
            label: 'SUGGESTIONS',
            padding: EdgeInsets.only(top: 24),
          ),
        ),
        epGutter(
          EpMenuRow(
            key: const Key('explore-suggest-near-me'),
            icon: Icons.near_me_outlined,
            label: 'Near me',
            padding: EdgeInsets.zero,
            onTap: () => _runSearch(app, 'near me'),
          ),
        ),
        epGutter(
          EpMenuRow(
            key: const Key('explore-suggest-tonight'),
            icon: Icons.nightlight_outlined,
            label: 'Tonight',
            padding: EdgeInsets.zero,
            onTap: () => _runSearch(app, 'tonight'),
          ),
        ),
        epGutter(
          EpMenuRow(
            key: const Key('explore-suggest-free'),
            icon: Icons.money_off_outlined,
            label: 'Free',
            padding: EdgeInsets.zero,
            onTap: () => _runSearch(app, 'free'),
          ),
        ),
        const SizedBox(height: tabBarClearance),
      ],
    );
  }

  Widget _resultsBody(BuildContext context, AppState app) {
    final hits = app.searchResults;
    final meta = searchMetaLine(app.parsedSearch, hits.length);
    final bands = app.bandSearchResults;
    return ListView(
      key: const ValueKey('explore-results'),
      padding: const EdgeInsets.only(top: _bodyTopInset),
      children: [
        if (bands.isNotEmpty) ...[
          epGutter(
            EpSectionHeader(
              key: const Key('explore-band-results'),
              label: 'BANDS',
              count: bands.length,
              padding: const EdgeInsets.only(top: 16, bottom: 4),
            ),
          ),
          for (final band in bands)
            epGutter(
              EpEntityRow(
                key: Key('explore-band-result-${band.id}'),
                leading: EpAvatarTile(
                  initials: band.initials,
                  image: switch (band.profileImageUrl) {
                    final url? when url.isNotEmpty => NetworkImage(url),
                    _ => null,
                  },
                ),
                title: band.name,
                sub: band.genres.isEmpty ? null : band.genres.join(' · '),
                subMaxLinesOne: true,
                onTap: () => app.openBand(band.id),
              ),
            ),
        ],
        epGutter(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 12),
            child: Text(
              meta,
              key: const Key('explore-results-meta'),
              style: Theme.of(
                context,
              ).textTheme.epLabel.copyWith(color: context.epColors.muted),
            ),
          ),
        ),
        if (hits.isEmpty)
          epGutter(
            Text(
              'Nothing matches. Try a band, a venue, a place, or tonight / free.',
              key: const Key('explore-no-results'),
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: context.epColors.muted),
            ),
          )
        else ...[
          epGutter(
            FanEventCard(
              key: const Key('explore-hero'),
              rowKey: const Key('explore-hero'),
              gig: hits.first.gig,
              app: app,
              showDistance: true,
              presentation: FanEventCardPresentation.featured,
            ),
          ),
          for (final hit in hits.skip(1))
            epGutter(
              FanEventCard(
                key: Key('explore-result-${hit.gig.id}'),
                rowKey: Key('explore-result-${hit.gig.id}'),
                gig: hit.gig,
                app: app,
                showDistance: true,
              ),
            ),
        ],
        const SizedBox(height: tabBarClearance),
      ],
    );
  }
}
