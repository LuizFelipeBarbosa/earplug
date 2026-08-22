import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/discovery_filters_sheet.dart';
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
      decoration: BoxDecoration(
        color: Ep.bg,
        border: Border(bottom: BorderSide(color: Ep.whiteA(.09))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image.asset('assets/images/listen_local_bw.png', height: 46),
              _SegmentedToggle(app: app),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _CityPill(app: app),
              const Spacer(),
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
          Row(
            children: [
              for (final chip in _shortcutChips(app)) ...[
                chip,
                const SizedBox(width: 6),
              ],
            ],
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
    Widget seg(String label, bool active, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: active ? Ep.blue : null,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: epText(
              size: 10.5,
              weight: FontWeight.w900,
              letterSpacing: .8,
              color: active ? Colors.white : Ep.inkA(.55),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Ep.card,
        border: Border.all(color: Ep.whiteA(.14)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          seg('LIST', !app.mapMode, () => app.setMapMode(false)),
          const SizedBox(width: 2),
          seg('MAP', app.mapMode, () => app.setMapMode(true)),
        ],
      ),
    );
  }
}

class _CityPill extends StatelessWidget {
  final AppState app;

  const _CityPill({required this.app});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDiscoveryLocationSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: Ep.whiteA(.2)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Ep.blue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${app.locationLabel} ▾',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: epText(
                size: 11.5,
                weight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
          ],
        ),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
      children: [
        if (feed.isNotEmpty) ...[
          Text(
            '${feed.length} GIGS NEAR YOU · NEAREST FIRST',
            style: epText(
              size: 11,
              weight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Ep.inkA(.5),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (feed.isEmpty) _DiscoveryEmptyState(app: app),
        for (final g in feed) ...[
          _FeedCard(gig: g, app: app),
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
            '0 GIGS NEAR YOU · NEAREST FIRST',
            style: epText(
              size: 10.5,
              weight: FontWeight.w900,
              letterSpacing: 1,
              color: Ep.inkA(.48),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            noGigs
                ? 'No upcoming gigs yet.\nWhen a band books one, it shows up here.'
                : "Nothing matches those filters.\nLoosen up — the scene's out there.",
            textAlign: TextAlign.center,
            style: epText(size: 13, color: Ep.inkA(.6), height: 1.4),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: primary ? Ep.blue : Ep.card,
          border: Border.all(color: primary ? Ep.blue : Ep.whiteA(.2)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: epText(
            size: 10,
            weight: FontWeight.w900,
            letterSpacing: .4,
            color: primary ? Colors.white : Ep.inkA(.75),
          ),
        ),
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  final Gig gig;
  final AppState app;

  const _FeedCard({required this.gig, required this.app});

  @override
  Widget build(BuildContext context) {
    final venue = app.venue(gig.venueId);
    final fly = app.flyer(gig.flyKey);
    return EpCard(
      padding: const EdgeInsets.all(11),
      radius: 14,
      onTap: () => app.openGig(gig.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GigFlyer(
            gig,
            fly,
            width: 74,
            height: 98,
            rotationDeg: -1.4,
            padding: const EdgeInsets.all(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  gig.title.toUpperCase(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: epDisplay(size: 9.5, color: fly.fg, height: 1.08),
                ),
                Text(
                  gig.dateShort,
                  style: epText(
                    size: 7,
                    weight: FontWeight.w800,
                    letterSpacing: .6,
                    color: fly.fg.withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        gig.title.toUpperCase(),
                        style: epDisplay(
                          size: 14.5,
                          letterSpacing: .2,
                          height: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PriceBadge(gig),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${venue.name} · ${app.distanceOf(venue)}',
                  style: epText(size: 12, color: Ep.inkA(.65)),
                ),
                const SizedBox(height: 3),
                Text(
                  gig.dateLine,
                  style: epText(
                    size: 12,
                    weight: FontWeight.w800,
                    letterSpacing: .4,
                    color: Ep.link,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  gig.desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: epText(size: 12, color: Ep.inkA(.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
