import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../memo.dart';
import '../models.dart';
import '../services/location_service.dart';
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
        ScreenHeader(bottomPadding: 14, child: _HomeHeader()),
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
        const SizedBox(height: 6),
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const EpLogo.full(
              key: ValueKey('home-logo'),
              width: null,
              height: 22,
            ),
            const Spacer(),
            _ViewControls(),
          ],
        ),
        const SizedBox(height: 16),
        hero,
        const SizedBox(height: 14),
        _QuickFilters(),
      ],
    );
  }
}

/// The date and current location control.
class _HeroEyebrow extends StatelessWidget {
  const _HeroEyebrow();

  @override
  Widget build(BuildContext context) {
    final today = context.read<AppState>().firstSelectableDiscoveryDate;
    final (:locationLabel, :usingCurrentLocation, :locating, :locationFailure) =
        context.select<
          AppState,
          ({
            String locationLabel,
            bool usingCurrentLocation,
            bool locating,
            LocationFailure? locationFailure,
          })
        >(
          (app) => (
            locationLabel: app.locationLabel,
            usingCurrentLocation: app.usingCurrentLocation,
            locating: app.locating,
            locationFailure: app.locationFailure,
          ),
        );
    final app = context.read<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            EpEyebrow.accent(
              '${weekdayNames[today.weekday - 1]} ${today.day} '
              '${monthNames[today.month - 1]} ·',
            ),
            _LocationLink(
              key: const ValueKey('home-location-control'),
              locationLabel: locationLabel,
              usingCurrentLocation: usingCurrentLocation,
              locating: locating,
              app: app,
            ),
          ],
        ),
        if (locationFailure case final failure?) ...[
          const SizedBox(height: 6),
          _LocationFailureNote(failure: failure, app: app),
        ],
      ],
    );
  }
}

class _LocationLink extends StatelessWidget {
  const _LocationLink({
    super.key,
    required this.locationLabel,
    required this.usingCurrentLocation,
    required this.locating,
    required this.app,
  });

  final String locationLabel;
  final bool usingCurrentLocation;
  final bool locating;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final text = locating
        ? 'LOCATING…'
        : usingCurrentLocation
        ? locationLabel
        : 'USE MY LOCATION';
    return Semantics(
      button: true,
      enabled: !locating,
      label: usingCurrentLocation
          ? 'Using your location. Switch off'
          : 'Use my location',
      excludeSemantics: true,
      child: InkWell(
        onTap: locating
            ? null
            : () => app.setUseCurrentLocation(!usingCurrentLocation),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            text,
            style: Theme.of(context).textTheme.epSection.copyWith(
              color: locating ? palette.muted : palette.accent,
              decoration: TextDecoration.underline,
              decorationColor: palette.accent,
            ),
          ),
        ),
      ),
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
        ? (72.0, 32.0)
        : MediaQuery.textScalerOf(context).scale(1) > 1.3
        ? (32.0, 16.0)
        : (44.0, 22.0);
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
    final sheetCount = _sheetFilterCount(filters);
    final tonight = EpPill(
      label: 'Tonight',
      selected: filters.date == DateFilter.tonight,
      onPressed: () => app.toggleDateFilter(DateFilter.tonight),
      expand: !showViewControls,
    );
    final thisWeek = EpPill(
      label: 'This week',
      selected: filters.date == DateFilter.week,
      onPressed: () => app.toggleDateFilter(DateFilter.week),
      expand: !showViewControls,
    );
    final free = EpPill(
      label: 'Free',
      selected: filters.price == PriceFilter.free,
      onPressed: app.toggleFree,
      expand: !showViewControls,
    );
    final icon = EpIconPill(
      key: const ValueKey('home-filters'),
      icon: Icons.tune,
      badge: sheetCount == 0 ? null : '$sheetCount',
      badgeKey: const Key('home-filters-count'),
      filled: false,
      semanticLabel: sheetCount == 0
          ? 'Filters'
          : 'Filters, $sheetCount active',
      onPressed: () => showDiscoveryFiltersSheet(context, showGenres: false),
    );
    if (showViewControls) {
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [tonight, thisWeek, free, icon, const _ViewControls()],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: tonight),
        const SizedBox(width: 8),
        Expanded(child: thisWeek),
        const SizedBox(width: 8),
        Expanded(child: free),
        const SizedBox(width: 8),
        icon,
      ],
    );
  }
}

int _sheetFilterCount(DiscoveryFilters filters) =>
    (filters.maxDistanceMiles != null ? 1 : 0) +
    (filters.price == PriceFilter.paid ? 1 : 0) +
    (filters.date == DateFilter.custom ? 1 : 0);

class _LocationFailureNote extends StatelessWidget {
  const _LocationFailureNote({required this.failure, required this.app})
    : super(key: const ValueKey('home-location-failure'));

  final LocationFailure failure;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final (message, action) = switch (failure.reason) {
      LocationFailureReason.servicesDisabled => (
        'Location services are off. Turn them on or switch it off.',
        'Open location settings',
      ),
      LocationFailureReason.permissionDeniedForever => (
        'Location access is blocked. Allow it in settings or switch it off.',
        'Open app settings',
      ),
      LocationFailureReason.permissionDenied => (
        'Location access was denied. You can try again or switch it off.',
        null,
      ),
      LocationFailureReason.unavailable => (
        'Your location is unavailable right now. Try again or switch it off.',
        null,
      ),
    };
    final palette = context.epColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, size: 14, color: palette.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: Theme.of(context).textTheme.epCaption),
              if (action != null && !kIsWeb)
                TextButton(
                  onPressed: app.openLocationRecoverySettings,
                  child: Text(action.toUpperCase(), semanticsLabel: action),
                ),
            ],
          ),
        ),
        EpIconPill(
          icon: Icons.close,
          semanticLabel: 'Dismiss',
          onPressed: app.dismissLocationFailure,
        ),
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
