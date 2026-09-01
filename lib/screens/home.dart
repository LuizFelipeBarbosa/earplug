import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/branding.dart';
import '../widgets/common.dart';
import '../widgets/discovery_filters_sheet.dart';
import '../widgets/fan_event_card.dart';
import '../widgets/map_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Column(
      children: [
        _Header(app: app),
        Expanded(
          child: app.mapMode
              ? GigMapView(
                  emptyState: _DiscoveryEmptyState(app: app, compact: true),
                )
              : _FeedList(app: app),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final AppState app;

  const _Header({required this.app});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, headerTopPad(context), 16, 10),
      decoration: const BoxDecoration(
        color: Ep.background,
        border: Border(bottom: BorderSide(color: Ep.border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const EpLogo.compact(height: 42),
              _SegmentedToggle(app: app),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _CityPill(app: app)),
              const SizedBox(width: 8),
              EpChip(
                label: app.activeFilterCount == 0
                    ? 'FILTERS'
                    : 'FILTERS · ${app.activeFilterCount}',
                active:
                    app.fGenres.isNotEmpty ||
                    app.fVenueId != null ||
                    app.fMaxDistanceMiles != null ||
                    app.fPrice == PriceFilter.paid ||
                    app.fDate == DateFilter.custom,
                onTap: () => showDiscoveryFiltersSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final chip in _shortcutChips(app)) chip],
          ),
        ],
      ),
    );
  }

  List<Widget> _shortcutChips(AppState app) {
    return [
      EpChip(
        label: 'TONIGHT',
        active: app.fDate == DateFilter.tonight,
        onTap: () => app.toggleDateFilter(DateFilter.tonight),
      ),
      EpChip(
        label: 'THIS WEEK',
        active: app.fDate == DateFilter.week,
        onTap: () => app.toggleDateFilter(DateFilter.week),
      ),
      EpChip(label: 'FREE', active: app.fFree, onTap: app.toggleFree),
    ];
  }
}

class _SegmentedToggle extends StatelessWidget {
  final AppState app;

  const _SegmentedToggle({required this.app});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, label: Text('LIST')),
        ButtonSegment(value: true, label: Text('MAP')),
      ],
      selected: {app.mapMode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => app.setMapMode(selection.single),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(56, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10),
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.epLabel.copyWith(letterSpacing: .8),
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
    );
  }
}

class _CityPill extends StatelessWidget {
  final AppState app;

  const _CityPill({required this.app});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => showDiscoveryLocationSheet(context),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        foregroundColor: Ep.contentPrimary,
      ),
      icon: const Icon(Icons.location_on, color: Ep.accent, size: 18),
      label: Text(
        '${app.locationLabel} ▾',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.epLabel,
      ),
    );
  }
}

class _FeedList extends StatelessWidget {
  final AppState app;

  const _FeedList({required this.app});

  @override
  Widget build(BuildContext context) {
    final feed = app.feed;
    final featured = feed.firstOrNull;
    final remaining = feed.skip(1).toList(growable: false);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
      children: [
        if (feed.isNotEmpty) ...[
          Text(
            '${feed.length} GIGS NEAR YOU · LOCAL ORDER',
            style: Theme.of(context).textTheme.epLabel.copyWith(
              letterSpacing: 1.2,
              color: Ep.contentSecondary,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (feed.isEmpty) _DiscoveryEmptyState(app: app),
        if (featured != null) ...[
          _FeedSection(
            label: 'FEATURED NEAR YOU',
            featured: featured,
            gigs: const [],
            app: app,
          ),
          for (final section in GigWhen.values)
            _FeedSection(
              label: switch (section) {
                GigWhen.tonight => 'TONIGHT',
                GigWhen.week => 'THIS WEEK',
                GigWhen.later => 'LATER',
              },
              featured: null,
              gigs: remaining
                  .where((gig) => gig.when == section)
                  .toList(growable: false),
              app: app,
            ),
        ],
      ],
    );
  }
}

class _FeedSection extends StatelessWidget {
  const _FeedSection({
    required this.label,
    required this.featured,
    required this.gigs,
    required this.app,
  });

  final String label;
  final Gig? featured;
  final List<Gig> gigs;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final count = gigs.length + (featured == null ? 0 : 1);
    if (count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(label: label, count: count),
        if (featured case final gig?) ...[
          if (app.isDiscoveryBoosted(gig)) ...[
            Text(
              'DISCOVERY BOOST · COMPLETE LISTING',
              key: ValueKey('discovery-boost-${gig.id}'),
              style: Theme.of(context).textTheme.epMeta.copyWith(
                color: Ep.accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: .45,
              ),
            ),
            const SizedBox(height: 6),
          ],
          FanEventCard(
            gig: gig,
            app: app,
            showDistance: true,
            presentation: FanEventCardPresentation.featured,
          ),
          const SizedBox(height: 10),
        ],
        for (final gig in gigs) ...[
          FanEventCard(gig: gig, app: app, showDistance: true),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _DiscoveryEmptyState extends StatelessWidget {
  const _DiscoveryEmptyState({required this.app, this.compact = false});

  final AppState app;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final noGigs = app.allGigs.isEmpty;
    return DashedBox(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 18 : 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '0 GIGS NEAR YOU · LOCAL ORDER',
            style: Theme.of(context).textTheme.epLabel.copyWith(
              letterSpacing: 1,
              color: Ep.contentSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            noGigs
                ? 'No upcoming gigs yet.\nWhen a band books one, it shows up here.'
                : 'Nothing matches those filters.\nLoosen them up and see what is out there.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: Ep.contentSecondary),
          ),
          if (!noGigs) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 7,
              children: _recoveryActions(app),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _recoveryActions(AppState app) {
    final actions = <Widget>[];
    switch (app.fDate) {
      case DateFilter.tonight:
        actions.add(
          _RecoveryButton(
            label: 'SHOW THIS WEEK',
            onTap: () => app.toggleDateFilter(DateFilter.week),
          ),
        );
      case DateFilter.week:
        actions.add(
          _RecoveryButton(label: 'SHOW ALL DATES', onTap: app.clearDateFilter),
        );
      case DateFilter.custom:
        actions.add(
          _RecoveryButton(
            label: 'WIDEN DATE RANGE',
            onTap: app.widenDateFilter,
          ),
        );
        actions.add(
          _RecoveryButton(label: 'CLEAR DATES', onTap: app.clearDateFilter),
        );
      case DateFilter.all:
        break;
    }

    if (app.fMaxDistanceMiles case final double distance) {
      final nextDistance = distance < 10
          ? 10.0
          : distance < 25
          ? 25.0
          : null;
      actions.add(
        _RecoveryButton(
          label: nextDistance == null
              ? 'ANY DISTANCE'
              : 'EXPAND TO ${nextDistance.toInt()} MI',
          onTap: () => app.setDistanceFilter(nextDistance),
        ),
      );
    }
    if (app.fGenres.isNotEmpty) {
      actions.add(
        _RecoveryButton(label: 'CLEAR GENRES', onTap: app.clearGenreFilters),
      );
    }
    if (app.fPrice != PriceFilter.any) {
      actions.add(
        _RecoveryButton(
          label: 'ANY PRICE',
          onTap: () => app.setPriceFilter(PriceFilter.any),
        ),
      );
    }
    if (app.fVenueId != null) {
      actions.add(
        _RecoveryButton(
          label: 'ANY VENUE',
          onTap: () => app.setVenueFilter(null),
        ),
      );
    }
    actions.add(
      _RecoveryButton(
        label: 'VIEW ALL NEARBY SHOWS',
        primary: true,
        onTap: app.clearDiscoveryFilters,
      ),
    );
    return actions;
  }
}

class _RecoveryButton extends StatelessWidget {
  const _RecoveryButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 11),
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.epLabel.copyWith(letterSpacing: .4),
      ),
    );
    return primary
        ? FilledButton(onPressed: onTap, style: style, child: Text(label))
        : OutlinedButton(onPressed: onTap, style: style, child: Text(label));
  }
}
