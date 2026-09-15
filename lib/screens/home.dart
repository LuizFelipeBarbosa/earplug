import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/branding.dart';
import '../widgets/common.dart';
import '../widgets/discovery_feed.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/location_eyebrow.dart';
import '../widgets/map_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mapMode = context.select<AppState, bool>((app) => app.mapMode);
    return Column(
      children: [
        ScreenHeader(bottomPadding: 14, child: _HomeHeader(mapMode)),
        Expanded(
          child: mapMode
              ? const GigMapView(
                  emptyState: _DiscoveryEmptyState(compact: true),
                )
              : const DiscoveryFeed(),
        ),
      ],
    );
  }
}

/// Identity and view controls, with location and nearby show count in map mode.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader(this.mapMode);

  final bool mapMode;

  @override
  Widget build(BuildContext context) {
    const identityRow = Row(
      key: ValueKey('home-header-row'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        EpLogo.full(key: ValueKey('home-logo'), width: null, height: 22),
        Spacer(),
        _ViewControls(),
      ],
    );
    if (!mapMode) return identityRow;

    final count = context.select<AppState, int>((app) => app.homeFeed.length);
    final hero = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DiscoveryLocationEyebrow(
          controlKey: ValueKey('home-location-control'),
          failureKey: ValueKey('home-location-failure'),
        ),
        const SizedBox(height: 6),
        _HeroTitle(count: count),
      ],
    );

    if (EpLayout.isDesktop(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: KeyedSubtree(
              key: const ValueKey('home-header-hero'),
              child: hero,
            ),
          ),
          const SizedBox(width: 24),
          const Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.bottomRight,
              child: _ViewControls(),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [identityRow, const SizedBox(height: 16), hero],
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final (numeral, labelSize) = EpLayout.isDesktop(context)
        ? (72.0, 48.0)
        : MediaQuery.textScalerOf(context).scale(1) > 1.3
        ? (32.0, 24.0)
        : (44.0, 32.0);
    return Semantics(
      key: const ValueKey('home-hero'),
      label: '$count ${count == 1 ? 'show' : 'shows'} near you.',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$count ',
                style: Theme.of(context).textTheme
                    .epDisplayAt(numeral)
                    .copyWith(color: palette.accent),
              ),
              TextSpan(
                text: count == 1 ? 'SHOW NEAR YOU.' : 'SHOWS NEAR YOU.',
                style: Theme.of(
                  context,
                ).textTheme.epDisplayAt(labelSize).copyWith(color: palette.ink),
              ),
            ],
          ),
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// Map/list segmented control.
class _ViewControls extends StatelessWidget {
  const _ViewControls();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final mapMode = context.select<AppState, bool>((value) => value.mapMode);
    return EpSegmentedControl(
      key: const ValueKey('home-view-toggle'),
      segments: const [
        EpSegment(
          key: Key('home-view-map'),
          icon: Icons.map_outlined,
          label: 'Map',
          semanticLabel: 'Map view',
        ),
        EpSegment(
          key: Key('home-view-list'),
          icon: Icons.view_list_outlined,
          label: 'List',
          semanticLabel: 'List view',
        ),
      ],
      selected: mapMode ? 0 : 1,
      onSelect: (index) => app.setMapMode(index == 0),
    );
  }
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
