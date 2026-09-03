import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../memo.dart';
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
    final mapMode = context.select<AppState, bool>((app) => app.mapMode);
    return Column(
      children: [
        const _Header(),
        Expanded(
          child: mapMode
              ? const GigMapView(
                  emptyState: _DiscoveryEmptyState(compact: true),
                )
              : const _FeedList(),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final filters = context.select<AppState, DiscoveryFilters>(
      (app) => app.filters,
    );
    return ScreenHeader(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const EpLogo.compact(key: ValueKey('home-logo'), height: 38),
              const SizedBox(width: 9),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: ExcludeSemantics(
                    child: Text(
                      'EARPLUG',
                      key: const ValueKey('home-wordmark'),
                      maxLines: 1,
                      style: epDisplay(size: 28, letterSpacing: 1.2, height: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const _SegmentedToggle(),
            ],
          ),
          const SizedBox(height: 10),
          const SizedBox(width: double.infinity, child: _CityPill()),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                EpChip(
                  label: filters.activeCount == 0
                      ? 'FILTERS'
                      : 'FILTERS · ${filters.activeCount}',
                  active:
                      filters.genres.isNotEmpty ||
                      filters.venueId != null ||
                      filters.maxDistanceMiles != null ||
                      filters.price == PriceFilter.paid ||
                      filters.date == DateFilter.custom,
                  onTap: () => showDiscoveryFiltersSheet(context),
                ),
                for (final chip in _shortcutChips(app, filters)) chip,
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _shortcutChips(AppState app, DiscoveryFilters filters) {
    return [
      EpChip(
        label: 'TONIGHT',
        active: filters.date == DateFilter.tonight,
        onTap: () => app.toggleDateFilter(DateFilter.tonight),
      ),
      EpChip(
        label: 'THIS WEEK',
        active: filters.date == DateFilter.week,
        onTap: () => app.toggleDateFilter(DateFilter.week),
      ),
      EpChip(
        label: 'FREE',
        active: filters.price == PriceFilter.free,
        onTap: app.toggleFree,
      ),
    ];
  }
}

class _SegmentedToggle extends StatelessWidget {
  const _SegmentedToggle();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final mapMode = context.select<AppState, bool>((app) => app.mapMode);
    return SegmentedButton<bool>(
      key: const ValueKey('home-view-toggle'),
      segments: const [
        ButtonSegment(value: false, label: Text('LIST')),
        ButtonSegment(value: true, label: Text('MAP')),
      ],
      selected: {mapMode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => app.setMapMode(selection.single),
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(56, 48)),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.epLabel.copyWith(letterSpacing: .8),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? context.epColors.surfaceSelected
              : context.epColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? context.epColors.contentPrimary
              : context.epColors.contentSecondary,
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: context.epColors.border),
        ),
      ),
    );
  }
}

class _CityPill extends StatelessWidget {
  const _CityPill();

  @override
  Widget build(BuildContext context) {
    final locationLabel = context.select<AppState, String>(
      (app) => app.locationLabel,
    );
    return OutlinedButton.icon(
      key: const ValueKey('home-location-control'),
      onPressed: () => showDiscoveryLocationSheet(context),
      style: OutlinedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        foregroundColor: context.epColors.contentPrimary,
      ),
      icon: Icon(Icons.location_on, color: context.epColors.accent, size: 18),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              locationLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.epLabel,
            ),
          ),
          Icon(Icons.arrow_drop_down, size: 18, color: context.epColors.accent),
        ],
      ),
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
      final rows = <_FeedRow>[];
      if (feed.isEmpty) {
        rows.add(const _FeedEmptyRow());
      } else {
        rows.add(_FeedCountRow(feed.length));

        final featured = feed.first;
        rows.add(const _FeedSectionRow(label: 'FEATURED NEAR YOU', count: 1));
        if (inputs.featuredBoosted) {
          rows.add(_FeedBoostRow(featured));
        }
        rows.add(_FeedCardRow(featured, featured: true));

        final remaining = feed.skip(1);
        for (final section in GigWhen.values) {
          final gigs = remaining
              .where((gig) => gig.when == section)
              .toList(growable: false);
          if (gigs.isEmpty) continue;

          rows.add(
            _FeedSectionRow(
              label: switch (section) {
                GigWhen.tonight => 'TONIGHT',
                GigWhen.week => 'THIS WEEK',
                GigWhen.later => 'LATER',
              },
              count: gigs.length,
            ),
          );
          for (final gig in gigs) {
            rows.add(_FeedCardRow(gig));
          }
        }
      }
      return rows;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rows = _feedRows(app);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, tabBarClearance),
      itemCount: rows.length,
      itemBuilder: (context, index) => _buildRow(context, rows[index], app),
    );
  }

  Widget _buildRow(BuildContext context, _FeedRow row, AppState app) {
    return switch (row) {
      _FeedCountRow(:final count) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          '$count ${count == 1 ? 'GIG' : 'GIGS'} NEAR YOU · LOCAL ORDER',
          style: Theme.of(context).textTheme.epLabel.copyWith(
            letterSpacing: 1.2,
            color: context.epColors.contentSecondary,
          ),
        ),
      ),
      _FeedEmptyRow() => const _DiscoveryEmptyState(),
      _FeedSectionRow(:final label, :final count) => SectionBar(
        label: label,
        count: count,
      ),
      _FeedBoostRow(:final gig) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          'DISCOVERY BOOST · COMPLETE LISTING',
          key: ValueKey('discovery-boost-${gig.id}'),
          style: Theme.of(context).textTheme.epMeta.copyWith(
            color: context.epColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: .45,
          ),
        ),
      ),
      _FeedCardRow(:final gig, :final featured) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FanEventCard(
          gig: gig,
          app: app,
          showDistance: true,
          presentation: featured
              ? FanEventCardPresentation.featured
              : FanEventCardPresentation.compact,
        ),
      ),
    };
  }
}

sealed class _FeedRow {
  const _FeedRow();
}

class _FeedCountRow extends _FeedRow {
  const _FeedCountRow(this.count);

  final int count;
}

class _FeedEmptyRow extends _FeedRow {
  const _FeedEmptyRow();
}

class _FeedSectionRow extends _FeedRow {
  const _FeedSectionRow({required this.label, required this.count});

  final String label;
  final int count;
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

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final (:noGigs, :filters) = context
        .select<AppState, ({bool noGigs, DiscoveryFilters filters})>(
          (app) => (noGigs: app.allGigs.isEmpty, filters: app.filters),
        );
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
              color: context.epColors.contentSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            noGigs
                ? 'No upcoming gigs yet.\nWhen a band books one, it shows up here.'
                : 'Nothing matches those filters.\nLoosen them up and see what is out there.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.epBody.copyWith(
              color: context.epColors.contentSecondary,
            ),
          ),
          if (!noGigs) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 7,
              children: _recoveryActions(app, filters),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _recoveryActions(AppState app, DiscoveryFilters filters) {
    final actions = <Widget>[];
    switch (filters.date) {
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

    if (filters.maxDistanceMiles case final double distance) {
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
    if (filters.genres.isNotEmpty) {
      actions.add(
        _RecoveryButton(label: 'CLEAR GENRES', onTap: app.clearGenreFilters),
      );
    }
    if (filters.price != PriceFilter.any) {
      actions.add(
        _RecoveryButton(
          label: 'ANY PRICE',
          onTap: () => app.setPriceFilter(PriceFilter.any),
        ),
      );
    }
    if (filters.venueId != null) {
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
      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 11)),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.epLabel.copyWith(letterSpacing: .4),
      ),
    );
    return primary
        ? FilledButton(onPressed: onTap, style: style, child: Text(label))
        : OutlinedButton(onPressed: onTap, style: style, child: Text(label));
  }
}
