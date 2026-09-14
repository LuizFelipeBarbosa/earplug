import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/ep_text.dart';
import './discovery_filters_sheet.dart';

/// Tonight / This week / Free quick filters plus the filters-sheet icon pill,
/// shared by the GIGS feed and the Explore page.
class DiscoveryQuickFilters extends StatelessWidget {
  const DiscoveryQuickFilters({
    super.key,
    this.filterButtonKey = const ValueKey('home-filters'),
    this.badgeKey = const Key('home-filters-count'),
    this.trailing,
  });

  final Key filterButtonKey;
  final Key badgeKey;

  /// e.g. the Map/List segmented control on desktop.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final filters = context.select<AppState, DiscoveryFilters>(
      (value) => value.filters,
    );
    final sheetCount = discoverySheetFilterCount(filters);
    final tonight = EpPill(
      label: 'Tonight',
      selected: filters.date == DateFilter.tonight,
      onPressed: () => app.toggleDateFilter(DateFilter.tonight),
      expand: trailing == null,
    );
    final thisWeek = EpPill(
      label: 'This week',
      selected: filters.date == DateFilter.week,
      onPressed: () => app.toggleDateFilter(DateFilter.week),
      expand: trailing == null,
    );
    final free = EpPill(
      label: 'Free',
      selected: filters.price == PriceFilter.free,
      onPressed: app.toggleFree,
      expand: trailing == null,
    );
    final icon = EpIconPill(
      key: filterButtonKey,
      icon: Icons.tune,
      badge: sheetCount == 0 ? null : '$sheetCount',
      badgeKey: badgeKey,
      filled: false,
      semanticLabel: sheetCount == 0
          ? 'Filters'
          : 'Filters, $sheetCount active',
      onPressed: () => showDiscoveryFiltersSheet(context, showGenres: false),
    );
    if (trailing != null) {
      return Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [tonight, thisWeek, free, icon, trailing!],
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

/// Distance + paid + custom date active-filter count for the filters-sheet
/// icon pill badge.
int discoverySheetFilterCount(DiscoveryFilters filters) =>
    (filters.maxDistanceMiles != null ? 1 : 0) +
    (filters.price == PriceFilter.paid ? 1 : 0) +
    (filters.date == DateFilter.custom ? 1 : 0);
