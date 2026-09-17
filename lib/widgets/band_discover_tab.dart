import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../genres.dart';
import '../models.dart';
import '../money.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_sheet.dart';
import 'ep_text.dart';
import 'form_bits.dart';
import 'sheets.dart';

class BandDiscoverTab extends StatefulWidget {
  const BandDiscoverTab({super.key});

  @override
  State<BandDiscoverTab> createState() => _BandDiscoverTabState();
}

enum _DateWindow {
  any('Any date', 'DATE', null),
  week('This week', 'THIS WEEK', 7),
  month('This month', 'THIS MONTH', 31);

  const _DateWindow(this.option, this.label, this.days);

  final String option;
  final String label;
  final int? days;
}

class _BandDiscoverTabState extends State<BandDiscoverTab> {
  final _search = TextEditingController();
  bool _requestedBrowse = false;
  bool _nearYou = true;
  bool _requestedLocation = false;
  bool _loadingMore = false;
  _DateWindow _date = _DateWindow.any;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestedBrowse) return;
    _requestedBrowse = true;
    final app = context.read<AppState>();
    scheduleMicrotask(() {
      if (mounted) unawaited(app.refreshBrowse());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleNearYou(AppState app) {
    // The default selection uses date order until the user requests a fix.
    // Its first tap can request location without first toggling it off.
    if (_nearYou && (app.currentPosition != null || _requestedLocation)) {
      setState(() => _nearYou = false);
      return;
    }
    setState(() => _nearYou = true);
    if (app.currentPosition == null) {
      _requestedLocation = true;
      unawaited(app.selectCurrentLocation());
    }
  }

  List<BrowseItem> _visibleItems(AppState app) {
    final byId = <String, BrowseItem>{};
    for (final item in [...app.browse.invited, ...app.browse.items]) {
      final existing = byId[item.opportunity.id];
      if (existing == null || (!existing.invited && item.invited)) {
        byId[item.opportunity.id] = item;
      }
    }
    final query = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final end = _date.days == null
        ? null
        : now.add(Duration(days: _date.days!));
    final items = byId.values.where((item) {
      final opportunity = item.opportunity;
      if (end != null &&
          (opportunity.startsAt.isBefore(now) ||
              opportunity.startsAt.isAfter(end))) {
        return false;
      }
      return query.isEmpty ||
          [
            opportunity.title,
            opportunity.venue?.name,
            opportunity.venue?.city,
            opportunity.venue?.neighborhood,
            opportunity.area,
          ].any((value) => value?.toLowerCase().contains(query) ?? false);
    }).toList();

    final distances = <String, double>{};
    if (_nearYou && app.currentPosition != null) {
      for (final item in items) {
        final venue = item.opportunity.venue;
        distances[item.opportunity.id] = venue == null
            ? double.infinity
            : app.distanceMilesFromCurrent(venue) ?? double.infinity;
      }
    }
    items.sort((a, b) {
      if (a.invited != b.invited) return a.invited ? -1 : 1;
      if (distances.isNotEmpty) {
        final distanceOrder = distances[a.opportunity.id]!.compareTo(
          distances[b.opportunity.id]!,
        );
        if (distanceOrder != 0) return distanceOrder;
      }
      final dateOrder = a.opportunity.startsAt.compareTo(
        b.opportunity.startsAt,
      );
      return dateOrder != 0
          ? dateOrder
          : a.opportunity.id.compareTo(b.opportunity.id);
    });
    return items;
  }

  void _showDate() => showEpActionSheet(
    context,
    header: 'Date',
    items: [
      for (final window in _DateWindow.values)
        EpActionSheetItem(
          label: window.option,
          onPressed: () => setState(() => _date = window),
        ),
    ],
  );

  void _showPay(AppState app) => showEpActionSheet(
    context,
    header: 'Pay',
    items: [
      for (final minimum in <int?>[null, 10000, 25000, 50000])
        EpActionSheetItem(
          label: minimum == null ? 'Any' : _minimumLabel(minimum),
          onPressed: () {
            final filters = app.browseFilters;
            app.setBrowseFilters(
              OpportunityFilters(
                area: filters.area,
                genre: filters.genre,
                venueType: filters.venueType,
                minGuaranteeMinor: minimum,
              ),
            );
          },
        ),
    ],
  );

  void _showGenre(AppState app) => showEpSheet(
    context,
    (_) => SingleChildScrollView(
      child: EpActionSheet(
        header: 'Genre',
        items: [
          for (final genre in <String?>[null, ...kGenres])
            EpActionSheetItem(
              label: genre ?? 'Any',
              onPressed: () {
                final filters = app.browseFilters;
                app.setBrowseFilters(
                  OpportunityFilters(
                    area: filters.area,
                    genre: genre,
                    venueType: filters.venueType,
                    minGuaranteeMinor: filters.minGuaranteeMinor,
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );

  Future<void> _loadMore(AppState app) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      await app.loadMoreOpportunities();
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final browse = app.browse;
    final filters = app.browseFilters;
    final items = _visibleItems(app);
    final moreFilterCount =
        (filters.area?.trim().isNotEmpty == true ? 1 : 0) +
        (filters.venueType == null ? 0 : 1);
    final loading = browse.status == DataStatus.connecting || _loadingMore;

    return RefreshIndicator(
      onRefresh: app.refreshBrowse,
      child: ListView(
        key: const PageStorageKey('band-discover'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          EpLayout.gutter,
          16,
          EpLayout.gutter,
          tabBarClearance,
        ),
        children: [
          EpUnderlineField(
            fieldKey: const Key('discover-search-field'),
            controller: _search,
            hint: 'Search gigs, venues, cities',
            icon: Icons.search,
            onChanged: (_) => setState(() {}),
            trailing: _search.text.isEmpty
                ? null
                : EpIconPill(
                    key: const Key('discover-search-clear'),
                    icon: Icons.close,
                    semanticLabel: 'Clear search',
                    onPressed: () => setState(_search.clear),
                  ),
          ),
          const SizedBox(height: 16),
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                ...ScrollConfiguration.of(context).dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  _DiscoverChip(
                    chipKey: const Key('discover-chip-near'),
                    label: 'Near you',
                    selected: _nearYou,
                    onPressed: () => _toggleNearYou(app),
                  ),
                  _DiscoverChip(
                    chipKey: const Key('discover-chip-date'),
                    label: _date.label,
                    selected: _date != _DateWindow.any,
                    onPressed: _showDate,
                  ),
                  _DiscoverChip(
                    chipKey: const Key('discover-chip-pay'),
                    label: filters.minGuaranteeMinor == null
                        ? 'Pay'
                        : _minimumLabel(filters.minGuaranteeMinor!),
                    selected: filters.minGuaranteeMinor != null,
                    onPressed: () => _showPay(app),
                  ),
                  _DiscoverChip(
                    chipKey: const Key('discover-chip-genre'),
                    label: filters.genre ?? 'Genre',
                    selected: filters.genre != null,
                    onPressed: () => _showGenre(app),
                  ),
                  EpIconPill(
                    key: const Key('discover-more-filters'),
                    icon: Icons.tune,
                    semanticLabel: 'More filters',
                    badge: moreFilterCount == 0 ? null : '$moreFilterCount',
                    badgeKey: const Key('discover-more-filters-count'),
                    onPressed: () => showEpSheet(
                      context,
                      (_) => _MoreFiltersSheet(app: app),
                    ),
                  ),
                ],
              ),
            ),
          ),
          EpSectionHeader(label: 'OPEN · ${items.length}'),
          if (browse.privateCount > 0) ...[
            EpMonoText(
              'Private events: the exact address is shared with the booked '
              'artist after the deposit is paid.',
              keepCase: true,
              color: context.epColors.contentSecondary,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          for (final item in items) ...[
            _DiscoverCard(item: item),
            const SizedBox(height: 12),
          ],
          if (items.isEmpty && _search.text.trim().isNotEmpty)
            const EmptyNote(
              message: 'No loaded gigs match. Load more to search further.',
            )
          else if (items.isEmpty && browse.status == DataStatus.ready)
            const EmptyNote(message: 'Nothing open right now.'),
          if (loading) const EpMonoText('LOADING…'),
          if (browse.status == DataStatus.error) ...[
            EmptyNote(message: browse.error ?? 'Could not load opportunities.'),
            SizedBox(
              height: 44,
              child: EpPill(label: 'Retry', onPressed: app.refreshBrowse),
            ),
          ],
          if (!browse.isDone) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: EpPill(
                key: const Key('band-gigs-load-more'),
                label: 'Load more',
                onPressed: loading ? null : () => _loadMore(app),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _minimumLabel(int minor) {
  final amount = minor % 100 == 0
      ? '${minor ~/ 100}'
      : (minor / 100).toStringAsFixed(2);
  return '\$$amount+';
}

/// Keeps the chip typography while giving the entire control a 44px target.
class _DiscoverChip extends StatelessWidget {
  const _DiscoverChip({
    this.chipKey,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final Key? chipKey;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: EpPill(
      key: chipKey,
      label: label,
      selected: selected,
      variant: selected ? EpPillVariant.primary : EpPillVariant.outline,
      onPressed: onPressed,
    ),
  );
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.item});

  final BrowseItem item;

  @override
  Widget build(BuildContext context) {
    final opportunity = item.opportunity;
    final venue = opportunity.venue;
    final private =
        opportunity.privateEvent ||
        opportunity.mode == OpportunityMode.privateBooking;
    final slots = opportunity.slots
        .where((slot) => slot.status == SlotStatus.open)
        .toList();
    final firstSlot = slots.firstOrNull;
    final applied = switch (item.myApplicationStatus) {
      null ||
      ArtistApplicationStatus.withdrawn ||
      ArtistApplicationStatus.declined ||
      ArtistApplicationStatus.expired => false,
      _ => true,
    };
    final deadline = _opportunityDate(opportunity.applicationsCloseAt);
    final spotsLeft = applied && slots.length <= 2;
    void openDetail() =>
        context.read<AppState>().openOpportunity(opportunity.slug);

    return EpCard(
      key: ValueKey('opp-card-${opportunity.id}'),
      radius: 0,
      borderColor: context.epColors.border,
      onTap: openDetail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EpDateBlock(date: opportunity.startsAt.toLocal()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EpDisplay(opportunity.title, size: 20, maxLines: 2),
                    const SizedBox(height: 8),
                    EpMonoText(
                      private || venue == null
                          ? opportunity.area
                          : '${venue.name} · ${venue.neighborhood ?? opportunity.area}',
                      keepCase: true,
                      color: context.epColors.contentSecondary,
                    ),
                    if (firstSlot != null) ...[
                      const SizedBox(height: 8),
                      EpMonoText(
                        '${firstSlot.role.name.toUpperCase()}'
                        '${slots.length > 1 ? ' + ${slots.length - 1} MORE' : ''}'
                        ' · ${firstSlot.guaranteeMinor > 0 ? '${Money(firstSlot.guaranteeMinor, opportunity.currency).label} guarantee' : 'unpaid'}',
                        keepCase: true,
                      ),
                    ],
                    if (item.invited) ...[
                      const SizedBox(height: 8),
                      const EpBadge(
                        label: 'INVITED',
                        tone: EpBadgeTone.selected,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (private) ...[
            const SizedBox(height: 12),
            EpPill(
              key: ValueKey('opp-card-${opportunity.id}-private'),
              label: 'Private event',
              selected: true,
            ),
            if (opportunity.expectedAttendance case final guests?) ...[
              const SizedBox(height: 4),
              EpMonoText(
                '~$guests guests',
                keepCase: true,
                color: context.epColors.contentSecondary,
              ),
            ],
          ],
          const SizedBox(height: 16),
          const EpHairline(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: spotsLeft
                    ? EpMonoText(
                        '${slots.length} ${slots.length == 1 ? 'spot' : 'spots'} left',
                        keepCase: true,
                        color: context.epColors.success,
                      )
                    : deadline == null
                    ? const SizedBox.shrink()
                    : Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: context.epColors.contentSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: EpMonoText(
                              'Apply by $deadline',
                              keepCase: true,
                              color: context.epColors.contentSecondary,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 44,
                child: applied
                    ? EpPill(
                        key: ValueKey('opp-card-${opportunity.id}-applied'),
                        label: 'Applied',
                        icon: Icons.check,
                        selected: true,
                      )
                    : EpPill(
                        key: ValueKey('opp-card-${opportunity.id}-apply'),
                        label: 'Apply',
                        variant: EpPillVariant.primary,
                        onPressed: openDetail,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _opportunityDate(DateTime? d) => d == null ? null : shortDateLabel(d);

class _MoreFiltersSheet extends StatefulWidget {
  const _MoreFiltersSheet({required this.app});

  final AppState app;

  @override
  State<_MoreFiltersSheet> createState() => _MoreFiltersSheetState();
}

class _MoreFiltersSheetState extends State<_MoreFiltersSheet> {
  late final _area = TextEditingController(text: widget.app.browseFilters.area);
  late VenueType? _venueType = widget.app.browseFilters.venueType;

  @override
  void dispose() {
    _area.dispose();
    super.dispose();
  }

  void _apply({bool clear = false}) {
    final filters = widget.app.browseFilters;
    final area = _area.text.trim();
    widget.app.setBrowseFilters(
      OpportunityFilters(
        area: clear || area.isEmpty ? null : area,
        venueType: clear ? null : _venueType,
        genre: filters.genre,
        minGuaranteeMinor: filters.minGuaranteeMinor,
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => EpFormSheet(
    title: 'More filters',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EpEyebrow('Area'),
        const SizedBox(height: 8),
        EpUnderlineField(
          fieldKey: const Key('band-gigs-filter-area'),
          controller: _area,
          hint: 'Any area',
        ),
        const EpSectionHeader(label: 'Venue type'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in VenueType.values)
              _DiscoverChip(
                label: type.wireValue,
                selected: _venueType == type,
                onPressed: () => setState(
                  () => _venueType = _venueType == type ? null : type,
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            SizedBox(
              height: 44,
              child: EpPill(
                label: 'Clear',
                onPressed: () => _apply(clear: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 44,
                child: EpPill(
                  key: const Key('band-gigs-filter-apply'),
                  label: 'Apply',
                  variant: EpPillVariant.primary,
                  onPressed: _apply,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
