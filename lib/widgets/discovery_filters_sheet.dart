import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_sheet.dart';
import 'sheets.dart';

void showDiscoveryFiltersSheet(
  BuildContext context, {
  bool labelConfirmationAsApply = false,
}) {
  showEpSheet(
    context,
    (context) => Consumer<AppState>(
      builder: (context, app, _) => _FiltersSheet(
        app: app,
        labelConfirmationAsApply: labelConfirmationAsApply,
      ),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.child,
    this.action,
    this.footer,
  });

  final String title;
  final Widget child;

  /// Sits beside Close in the pinned header, so it stays reachable while the
  /// body scrolls without taking height from it.
  final Widget? action;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return EpSheetShell(
      heightFactor: .88,
      padding: const EdgeInsets.all(20),
      handleBottomSpacing: 12,
      header: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              semanticsLabel: title,
              style: Theme.of(context).textTheme.epSheetTitle,
            ),
          ),
          if (action != null) Flexible(child: action!),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 4),
        Expanded(child: child),
        if (footer case final Widget footer) ...[
          const SizedBox(height: 12),
          footer,
        ],
      ],
    );
  }
}

class _FiltersSheet extends StatelessWidget {
  const _FiltersSheet({
    required this.app,
    required this.labelConfirmationAsApply,
  });

  final AppState app;
  final bool labelConfirmationAsApply;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Filters',
      action: TextButton(
        key: const Key('clear-discovery-filters'),
        onPressed: app.activeFilterCount == 0
            ? null
            : app.clearDiscoveryFilters,
        child: Text('Clear all'.toUpperCase(), semanticsLabel: 'Clear all'),
      ),
      footer: _ResultsButton(
        count: app.feed.length,
        labelAsApply: labelConfirmationAsApply,
      ),
      child: ListView(
        key: const Key('discovery-filter-options'),
        children: [
          SectionBar(
            label: 'DATE',
            trailing: app.fDate != DateFilter.all
                ? _TextAction(label: 'CLEAR DATE', onTap: app.clearDateFilter)
                : null,
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              EpChip(
                label: 'Any date',
                active: app.fDate == DateFilter.all,
                onTap: app.clearDateFilter,
              ),
              EpChip(
                label: 'Tonight',
                active: app.fDate == DateFilter.tonight,
                onTap: () => app.toggleDateFilter(DateFilter.tonight),
              ),
              EpChip(
                label: 'This week',
                active: app.fDate == DateFilter.week,
                onTap: () => app.toggleDateFilter(DateFilter.week),
              ),
              EpChip(
                label: _dateRangeLabel(context, app.fDateRange),
                active: app.fDate == DateFilter.custom,
                onTap: app.canSelectCustomDate
                    ? () => _pickDateRange(context, app)
                    : null,
              ),
            ],
          ),
          const _Divider(),
          SectionBar(
            label: 'GENRES · CHOOSE ANY',
            trailing: app.fGenres.isNotEmpty
                ? _TextAction(
                    label: 'CLEAR GENRES',
                    onTap: app.clearGenreFilters,
                  )
                : null,
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              EpChip(
                label: "Any genre · I'm open",
                active: app.fGenres.isEmpty,
                onTap: app.clearGenreFilters,
              ),
              for (final genre in kGenres)
                EpChip(
                  label: genre,
                  active: app.fGenres.contains(genre),
                  onTap: () => app.toggleGenre(genre),
                ),
            ],
          ),
          const _Divider(),
          const SectionBar(label: 'DISTANCE'),
          const SizedBox(height: 5),
          Text(switch (app.discoveryLocation) {
            DiscoveryLocation.current => 'Measured from your current location.',
            DiscoveryLocation.home => 'Measured from your saved home location.',
            _ => 'Turn on Use my location to filter by distance.',
          }, style: Theme.of(context).textTheme.epCaption),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _ChoiceChip(
                label: 'Any',
                selected: app.fMaxDistanceMiles == null,
                onTap: app.canFilterByDistance
                    ? () => app.setDistanceFilter(null)
                    : null,
              ),
              for (final miles in const [5.0, 10.0, 25.0])
                _ChoiceChip(
                  label: '${miles.toInt()} MI',
                  selected: app.fMaxDistanceMiles == miles,
                  onTap: app.canFilterByDistance
                      ? () => app.setDistanceFilter(miles)
                      : null,
                ),
            ],
          ),
          const _Divider(),
          const SectionBar(label: 'PRICE'),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in PriceFilter.values)
                _ChoiceChip(
                  label: switch (option) {
                    PriceFilter.any => 'Any',
                    PriceFilter.free => 'Free',
                    PriceFilter.paid => 'Paid',
                  },
                  selected: app.fPrice == option,
                  onTap: () => app.setPriceFilter(option),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static String _dateRangeLabel(BuildContext context, DateTimeRange? range) {
    if (range == null) return 'Date or range';
    final localizations = MaterialLocalizations.of(context);
    final start = localizations.formatShortDate(range.start);
    final end = localizations.formatShortDate(range.end);
    return start == end ? start : '$start – $end';
  }

  static Future<void> _pickDateRange(BuildContext context, AppState app) async {
    final firstDate = app.firstSelectableDiscoveryDate;
    final lastDate = app.lastSelectableDiscoveryDate;
    final initial = app.fDateRange;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDateRange:
          initial == null ||
              initial.start.isBefore(firstDate) ||
              initial.end.isAfter(lastDate)
          ? null
          : initial,
      helpText: 'CHOOSE A DATE OR RANGE',
      saveText: 'USE DATES',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: context.epColors.accent,
            surface: context.epColors.surfaceRaised,
          ),
        ),
        child: child!,
      ),
    );
    if (selected != null) app.setDateRange(selected);
  }
}

class _ResultsButton extends StatelessWidget {
  const _ResultsButton({required this.count, required this.labelAsApply});

  final int count;
  final bool labelAsApply;

  @override
  Widget build(BuildContext context) {
    final label =
        '${labelAsApply ? 'APPLY FILTERS · ' : 'SHOW '}'
        '$count ${count == 1 ? 'RESULT' : 'RESULTS'}';
    return FilledButton(
      key: const Key('show-filter-results'),
      onPressed: () => Navigator.pop(context),
      child: Text(label.toUpperCase(), semanticsLabel: label),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return EpChip(label: label, active: selected, onTap: onTap);
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(label.toUpperCase(), semanticsLabel: label),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Divider(height: 1),
    );
  }
}
