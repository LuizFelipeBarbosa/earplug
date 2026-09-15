import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../search_query.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/fan_event_card.dart';

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
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EpDisplay('Explore', size: 44),
                const SizedBox(height: 16),
                _searchField(context, app),
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

  Widget _searchField(BuildContext context, AppState app) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    child: Builder(
      builder: (context) {
        final focused = Focus.of(context).hasFocus;
        return Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: focused ? context.epColors.accent : context.epColors.line,
              width: focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 16, color: context.epColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('explore-search-field'),
                  controller: _controller,
                  onChanged: (text) => _updateQuery(app, text),
                  onSubmitted: (text) => app.recordSearch(text),
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.epInput,
                  decoration: InputDecoration(
                    hintText: 'Events, bands, venues, places, tonight, free…',
                    hintStyle: Theme.of(
                      context,
                    ).textTheme.epInput.copyWith(color: context.epColors.muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        key: const Key('explore-search-clear'),
                        tooltip: 'Clear search',
                        onPressed: () => _clearSearch(app),
                        color: context.epColors.muted,
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _defaultBody(BuildContext context, AppState app) {
    final recents = app.recentSearches;
    return ListView(
      key: const ValueKey('explore-default'),
      padding: EdgeInsets.zero,
      children: [
        if (recents.isNotEmpty) ...[
          _gutter(const EpSectionHeader(label: 'RECENT SEARCHES')),
          for (var i = 0; i < recents.length; i++)
            _gutter(
              EpMenuRow(
                key: Key('explore-recent-$i'),
                icon: Icons.history,
                label: recents[i],
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
        _gutter(const EpSectionHeader(label: 'SUGGESTIONS')),
        _gutter(
          EpMenuRow(
            key: const Key('explore-suggest-near-me'),
            icon: Icons.near_me_outlined,
            label: 'Near me',
            onTap: () => _runSearch(app, 'near me'),
          ),
        ),
        _gutter(
          EpMenuRow(
            key: const Key('explore-suggest-tonight'),
            icon: Icons.nightlight_outlined,
            label: 'Tonight',
            onTap: () => _runSearch(app, 'tonight'),
          ),
        ),
        _gutter(
          EpMenuRow(
            key: const Key('explore-suggest-free'),
            icon: Icons.money_off_outlined,
            label: 'Free',
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
    return ListView(
      key: const ValueKey('explore-results'),
      padding: EdgeInsets.zero,
      children: [
        _gutter(
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
          _gutter(
            Text(
              'Nothing matches. Try a band, a venue, a place, or tonight / free.',
              key: const Key('explore-no-results'),
              style: Theme.of(
                context,
              ).textTheme.epBody.copyWith(color: context.epColors.muted),
            ),
          )
        else ...[
          _gutter(
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
            _gutter(
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

Widget _gutter(Widget child) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
  child: child,
);
