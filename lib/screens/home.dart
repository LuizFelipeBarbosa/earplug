import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../memo.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/branding.dart';
import '../widgets/common.dart';
import '../widgets/discovery_filters_sheet.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/map_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mapMode = context.select<AppState, bool>((app) => app.mapMode);
    if (!mapMode) return const _FeedList();
    return const Column(
      children: [
        ScreenHeader(bottomPadding: 20, child: _HomeHeader()),
        Expanded(
          child: GigMapView(emptyState: _DiscoveryEmptyState(compact: true)),
        ),
      ],
    );
  }
}

/// Identity row, the "N shows near you" hero and the quick filters. Fixed above
/// the map; the first thing the feed scrolls past in list mode.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final count = context.select<AppState, int>((app) => app.feed.length);
    final hero = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HeroEyebrow(),
        const SizedBox(height: 12),
        _HeroTitle(count: count),
      ],
    );

    if (EpLayout.isDesktop(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(flex: 3, child: hero),
          const SizedBox(width: 24),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.bottomRight,
              child: _QuickFilters(showViewControls: true),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const EpLogo.compact(key: ValueKey('home-logo'), height: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _ViewControls(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        hero,
        const SizedBox(height: 20),
        _QuickFilters(),
      ],
    );
  }
}

/// "FRI 11 SEP · MISSION, SF" — the date, then the location picker.
class _HeroEyebrow extends StatelessWidget {
  const _HeroEyebrow();

  @override
  Widget build(BuildContext context) {
    final today = context.read<AppState>().firstSelectableDiscoveryDate;
    final locationLabel = context.select<AppState, String>(
      (app) => app.locationLabel,
    );
    final palette = context.epColors;
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        EpEyebrow.accent(
          '${weekdayNames[today.weekday - 1]} ${today.day} '
          '${monthNames[today.month - 1]} ·',
        ),
        Semantics(
          button: true,
          label: 'Change location, $locationLabel',
          excludeSemantics: true,
          child: InkWell(
            key: const ValueKey('home-location-control'),
            onTap: () => showDiscoveryLocationSheet(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: EpMonoText(locationLabel, color: palette.accent),
                  ),
                  Icon(Icons.expand_more, size: 16, color: palette.accent),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final size = EpLayout.isDesktop(context)
        ? 72.0
        : MediaQuery.textScalerOf(context).scale(1) > 1.3
        ? 32.0
        : 44.0;
    final label = '$count ${count == 1 ? 'show' : 'shows'} near you';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label.toUpperCase()),
          TextSpan(
            text: '.',
            style: TextStyle(color: palette.accent),
          ),
        ],
      ),
      semanticsLabel: '$label.',
      style: Theme.of(
        context,
      ).textTheme.epDisplayAt(size).copyWith(color: palette.ink),
    );
  }
}

/// Map toggle and the filter sheet, as the artboard's two header pills.
class _ViewControls extends StatelessWidget {
  const _ViewControls();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final mapMode = context.select<AppState, bool>((value) => value.mapMode);
    final filters = context.select<AppState, DiscoveryFilters>(
      (value) => value.filters,
    );
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        EpPill(
          key: const ValueKey('home-view-toggle'),
          label: 'Map',
          selected: mapMode,
          semanticLabel: mapMode ? 'Switch to list' : 'Switch to map',
          onPressed: () => app.setMapMode(!mapMode),
        ),
        EpPill(
          label: filters.activeCount == 0
              ? 'Filters'
              : 'Filters · ${filters.activeCount}',
          selected:
              filters.genres.isNotEmpty ||
              filters.maxDistanceMiles != null ||
              filters.price == PriceFilter.paid ||
              filters.date == DateFilter.custom,
          onPressed: () => showDiscoveryFiltersSheet(context),
        ),
      ],
    );
  }
}

/// Tonight / This week / Free, plus the view controls where the header has no
/// separate identity row (desktop).
class _QuickFilters extends StatelessWidget {
  const _QuickFilters({this.showViewControls = false});

  final bool showViewControls;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final filters = context.select<AppState, DiscoveryFilters>(
      (value) => value.filters,
    );
    return Wrap(
      alignment: showViewControls ? WrapAlignment.end : WrapAlignment.start,
      spacing: 8,
      runSpacing: 8,
      children: [
        EpPill(
          label: 'Tonight',
          selected: filters.date == DateFilter.tonight,
          onPressed: () => app.toggleDateFilter(DateFilter.tonight),
        ),
        EpPill(
          label: 'This week',
          selected: filters.date == DateFilter.week,
          onPressed: () => app.toggleDateFilter(DateFilter.week),
        ),
        EpPill(
          label: 'Free',
          selected: filters.price == PriceFilter.free,
          onPressed: app.toggleFree,
        ),
        if (showViewControls) const _ViewControls(),
      ],
    );
  }
}

class _FeedList extends StatefulWidget {
  const _FeedList();

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  final Memo<({List<Gig> feed, bool featuredBoosted}), List<_FeedRow>>
  _rowsMemo = Memo();

  /// Partitions the feed into rows once per feed instance. The list itself
  /// rebuilds on every AppState notification because its cards read live
  /// RSVP and going-count state off [app].
  List<_FeedRow> _feedRows(AppState app) {
    final feed = app.feed;
    final inputs = (
      feed: feed,
      featuredBoosted: feed.isNotEmpty && app.isDiscoveryBoosted(feed.first),
    );
    return _rowsMemo(inputs, () {
      if (feed.isEmpty) return const [_FeedEmptyRow()];

      final featured = feed.first;
      final rows = <_FeedRow>[
        _FeedSectionRow(
          label: 'Featured · ${_sectionLabel(featured.when)}',
          topLine: true,
        ),
        if (inputs.featuredBoosted) _FeedBoostRow(featured),
        _FeedCardRow(featured, featured: true),
      ];

      final remaining = feed.skip(1);
      for (final section in GigWhen.values) {
        final gigs = remaining
            .where((gig) => gig.when == section)
            .toList(growable: false);
        if (gigs.isEmpty) continue;
        rows.add(
          _FeedSectionRow(label: '${_sectionLabel(section)} · ${gigs.length}'),
        );
        for (final gig in gigs) {
          rows.add(_FeedCardRow(gig));
        }
      }
      return rows;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rows = _feedRows(app);
    if (EpLayout.isDesktop(context)) return _desktopFeed(context, app, rows);
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        tabBarClearance,
      ),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) => index == 0
          ? const _HomeHeader()
          : _buildRow(context, rows[index - 1], app),
    );
  }

  /// Wide screens run the lead poster and the dated rows side by side, so the
  /// row list is split at the featured card instead of stacked.
  Widget _desktopFeed(BuildContext context, AppState app, List<_FeedRow> rows) {
    final lead = rows.indexWhere((row) => row is _FeedCardRow && row.featured);
    Widget column(Iterable<_FeedRow> source) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final row in source) _buildRow(context, row, app)],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _HomeHeader(),
          const SizedBox(height: 32),
          const EpHairline(),
          if (lead == -1)
            column(rows)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: column(rows.take(lead + 1))),
                const SizedBox(width: 40),
                Expanded(child: column(rows.skip(lead + 1))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _FeedRow row, AppState app) {
    return switch (row) {
      _FeedEmptyRow() => const _DiscoveryEmptyState(),
      _FeedSectionRow(:final label, :final topLine) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topLine && !EpLayout.isDesktop(context)) const EpHairline(),
          EpSectionHeader(label: label),
        ],
      ),
      _FeedBoostRow(:final gig) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: EpEyebrow.accent(
          'Discovery boost · complete listing',
          key: ValueKey('discovery-boost-${gig.id}'),
        ),
      ),
      _FeedCardRow(:final gig, :final featured) => FanEventCard(
        gig: gig,
        app: app,
        showDistance: true,
        presentation: featured
            ? FanEventCardPresentation.featured
            : FanEventCardPresentation.compact,
      ),
    };
  }
}

String _sectionLabel(GigWhen when) => switch (when) {
  GigWhen.tonight => 'Tonight',
  GigWhen.week => 'This week',
  GigWhen.later => 'Later',
};

sealed class _FeedRow {
  const _FeedRow();
}

class _FeedEmptyRow extends _FeedRow {
  const _FeedEmptyRow();
}

class _FeedSectionRow extends _FeedRow {
  const _FeedSectionRow({required this.label, this.topLine = false});

  final String label;
  final bool topLine;
}

class _FeedBoostRow extends _FeedRow {
  const _FeedBoostRow(this.gig);

  final Gig gig;
}

class _FeedCardRow extends _FeedRow {
  const _FeedCardRow(this.gig, {this.featured = false});

  final Gig gig;
  final bool featured;
}

class _DiscoveryEmptyState extends StatelessWidget {
  const _DiscoveryEmptyState({this.compact = false});

  /// The map overlay: a panel so the copy stays legible over the tiles.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final (:noGigs, :filters) = context
        .select<AppState, ({bool noGigs, DiscoveryFilters filters})>(
          (app) => (noGigs: app.allGigs.isEmpty, filters: app.filters),
        );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          noGigs
              ? 'No upcoming gigs yet.\nWhen a band books one, it shows up here.'
              : 'Nothing matches those filters.\nLoosen them up and see what is out there.',
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
        if (!noGigs) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recoveryActions(app, filters),
          ),
        ],
      ],
    );
    if (!compact) {
      return Padding(padding: const EdgeInsets.only(top: 24), child: body);
    }
    return EpPanel(padding: const EdgeInsets.all(16), child: body);
  }

  List<Widget> _recoveryActions(AppState app, DiscoveryFilters filters) {
    final actions = <Widget>[];
    switch (filters.date) {
      case DateFilter.tonight:
        actions.add(
          EpPill(
            label: 'Show this week',
            onPressed: () => app.toggleDateFilter(DateFilter.week),
          ),
        );
      case DateFilter.week:
        actions.add(
          EpPill(label: 'Show all dates', onPressed: app.clearDateFilter),
        );
      case DateFilter.custom:
        actions.add(
          EpPill(label: 'Widen date range', onPressed: app.widenDateFilter),
        );
        actions.add(
          EpPill(label: 'Clear dates', onPressed: app.clearDateFilter),
        );
      case DateFilter.all:
        break;
    }

    if (filters.maxDistanceMiles case final double distance) {
      final nextDistance = distance < 10
          ? 10.0
          : distance < 25
          ? 25.0
          : null;
      actions.add(
        EpPill(
          label: nextDistance == null
              ? 'Any distance'
              : 'Expand to ${nextDistance.toInt()} mi',
          onPressed: () => app.setDistanceFilter(nextDistance),
        ),
      );
    }
    if (filters.genres.isNotEmpty) {
      actions.add(
        EpPill(label: 'Clear genres', onPressed: app.clearGenreFilters),
      );
    }
    if (filters.price != PriceFilter.any) {
      actions.add(
        EpPill(
          label: 'Any price',
          onPressed: () => app.setPriceFilter(PriceFilter.any),
        ),
      );
    }
    actions.add(
      EpPill(
        label: 'View all nearby shows',
        variant: EpPillVariant.primary,
        onPressed: app.clearDiscoveryFilters,
      ),
    );
    return actions;
  }
}
