import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../genres.dart';
import '../models.dart';
import '../services/location_service.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_sheet.dart';

void showDiscoveryLocationSheet(BuildContext context) {
  showEpSheet(
    context,
    (context) => Consumer<AppState>(
      builder: (context, app, _) => _LocationSheet(app: app),
    ),
  );
}

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
  const _SheetFrame({required this.title, required this.child, this.footer});

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .88;
    return SafeArea(
      top: false,
      child: Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: BoxDecoration(
          color: context.epColors.surfaceRaised,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: context.epColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.epColors.contentDisabled,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.epSectionHeading,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(child: child),
            if (footer case final Widget footer) ...[
              const SizedBox(height: 12),
              footer,
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationSheet extends StatelessWidget {
  const _LocationSheet({required this.app});

  final AppState app;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'WHERE ARE YOU?',
      child: ListView(
        children: [
          Text(
            'Use your position once, or pick a scene manually.',
            style: Theme.of(context).textTheme.epBody.copyWith(
              color: context.epColors.contentSecondary,
            ),
          ),
          const SizedBox(height: 10),
          _OptionTile(
            key: const Key('current-location-option'),
            title: 'Current location',
            subtitle: app.locating
                ? 'Finding you…'
                : 'Foreground location · not stored',
            selected: app.discoveryLocation == DiscoveryLocation.current,
            leading: app.locating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.my_location,
                    color: context.epColors.accent,
                    size: 20,
                  ),
            onTap: app.locating
                ? null
                : () async {
                    final selected = await app.selectCurrentLocation();
                    if (selected && context.mounted) Navigator.pop(context);
                  },
          ),
          if (app.locationFailure case final LocationFailure failure) ...[
            const SizedBox(height: 8),
            _LocationFailureMessage(failure: failure, app: app),
          ],
          if (app.discoveryLocation == DiscoveryLocation.home)
            if (app.discoveryHomeCity case final homeCity?)
              _OptionTile(
                title: homeCity.label,
                subtitle: 'Saved home location',
                selected: true,
                leading: Icon(Icons.home_outlined, size: 20),
                onTap: () => Navigator.pop(context),
              ),
          _OptionTile(
            title: 'Mission, SF',
            subtitle: 'San Francisco',
            selected: app.discoveryLocation == DiscoveryLocation.sf,
            leading: Icon(Icons.location_on_outlined, size: 20),
            onTap: () {
              app.setCity('sf');
              Navigator.pop(context);
            },
          ),
          _OptionTile(
            title: 'Temescal, OAK',
            subtitle: 'Oakland',
            selected: app.discoveryLocation == DiscoveryLocation.oak,
            leading: Icon(Icons.location_on_outlined, size: 20),
            onTap: () {
              app.setCity('oak');
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _LocationFailureMessage extends StatelessWidget {
  const _LocationFailureMessage({required this.failure, required this.app});

  final LocationFailure failure;
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final (message, action) = switch (failure.reason) {
      LocationFailureReason.servicesDisabled => (
        'Location services are off. Turn them on or choose a city below.',
        'OPEN LOCATION SETTINGS',
      ),
      LocationFailureReason.permissionDeniedForever => (
        'Location access is blocked. Allow it in settings or choose a city.',
        'OPEN APP SETTINGS',
      ),
      LocationFailureReason.permissionDenied => (
        'Location access was denied. You can try again or choose a city.',
        null,
      ),
      LocationFailureReason.unavailable => (
        'Your location is unavailable right now. Try again or choose a city.',
        null,
      ),
    };

    return EpCard(
      padding: const EdgeInsets.all(12),
      borderColor: context.epColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.epBody),
          if (action != null) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: app.openLocationRecoverySettings,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(action),
            ),
          ],
        ],
      ),
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
      title: 'FILTERS',
      footer: _ResultsButton(
        count: app.feed.length,
        labelAsApply: labelConfirmationAsApply,
      ),
      child: ListView(
        children: [
          Row(
            children: [
              const Expanded(child: _FilterHeading('DATE')),
              if (app.fDate != DateFilter.all)
                _TextAction(label: 'CLEAR DATE', onTap: app.clearDateFilter),
            ],
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
          Row(
            children: [
              const Expanded(child: _FilterHeading('GENRES · CHOOSE ANY')),
              if (app.fGenres.isNotEmpty)
                _TextAction(
                  label: 'CLEAR GENRES',
                  onTap: app.clearGenreFilters,
                ),
            ],
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
          const _FilterHeading('DISTANCE'),
          const SizedBox(height: 5),
          Text(switch (app.discoveryLocation) {
            DiscoveryLocation.current => 'Measured from your current location.',
            DiscoveryLocation.home => 'Measured from your saved home location.',
            _ => 'Choose Current location to filter by distance.',
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
          const _FilterHeading('PRICE'),
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
          const _Divider(),
          Row(
            children: [
              const Expanded(child: _FilterHeading('VENUE')),
              if (app.fVenueId != null)
                _TextAction(
                  label: 'ANY VENUE',
                  onTap: () => app.setVenueFilter(null),
                ),
            ],
          ),
          const SizedBox(height: 9),
          _OptionTile(
            title: 'Any venue',
            selected: app.fVenueId == null,
            onTap: () => app.setVenueFilter(null),
          ),
          for (final venue in app.venues)
            _OptionTile(
              title: venue.name,
              subtitle: venue.area,
              selected: app.fVenueId == venue.id,
              onTap: () => app.setVenueFilter(venue.id),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: app.activeFilterCount == 0
                ? null
                : app.clearDiscoveryFilters,
            child: Text('CLEAR ALL'),
          ),
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
            primary: Ep.brand,
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
    return FilledButton(
      key: const Key('show-filter-results'),
      onPressed: () => Navigator.pop(context),
      child: Text(
        '${labelAsApply ? 'APPLY FILTERS · ' : 'SHOW '}'
        '$count ${count == 1 ? 'RESULT' : 'RESULTS'}',
        style: Theme.of(context).textTheme.epLabel.copyWith(letterSpacing: .8),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: EpCard(
        variant: onTap == null
            ? EpCardVariant.disabled
            : selected
            ? EpCardVariant.selected
            : EpCardVariant.standard,
        // Passing a callback lets EpCard expose button semantics; the disabled
        // variant still suppresses the actual InkWell and reports enabled=false.
        onTap: onTap ?? () {},
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        radius: 10,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.epBody.copyWith(
                      fontWeight: FontWeight.w700,
                      color: onTap == null
                          ? context.epColors.contentDisabled
                          : context.epColors.contentPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.epCaption.copyWith(
                        color: onTap == null
                            ? context.epColors.contentDisabled
                            : context.epColors.contentSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                color: context.epColors.accent,
                size: 19,
              ),
          ],
        ),
      ),
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

class _FilterHeading extends StatelessWidget {
  const _FilterHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.epLabel.copyWith(
        letterSpacing: 1,
        color: context.epColors.contentSecondary,
      ),
    );
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
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label),
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
