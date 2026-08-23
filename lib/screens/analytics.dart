import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../date_names.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/sheets.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final band = app.myBand;
    if (band == null) return const SizedBox.shrink();

    final recap = app.bandRecap(band.id);
    final error = app.bandRecapError(band.id);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        headerTopPad(context),
        16,
        tabBarClearance,
      ),
      children: [
        Text('FAN ANALYTICS', style: Theme.of(context).textTheme.epPageHeading),
        const SizedBox(height: 5),
        _bandSelector(context, band),
        const SizedBox(height: 14),
        ..._bodyFor(app, band, recap, error),
      ],
    );
  }

  /// The recap covers one band, and this tab carries no other band identity —
  /// on an account in several bands the reader cannot otherwise tell whose
  /// shows are missing when the recap comes back empty.
  Widget _bandSelector(BuildContext context, Band band) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => showSwitcherSheet(context),
        child: Text('${band.name.toUpperCase()} ▾'),
      ),
    );
  }

  List<Widget> _bodyFor(
    AppState app,
    Band band,
    BandRecap? recap,
    String? error,
  ) {
    if (recap == null) {
      if (error == null) return [_loadingState()];
      return [_errorState(app, band.id, error)];
    }
    if (recap.shows.isEmpty) {
      return [_emptyState(band.name, hasOtherBands: app.myBands.length > 1)];
    }

    return [
      _privacyNote(),
      const SizedBox(height: 14),
      _headline(recap),
      const SizedBox(height: 14),
      _turnoutByShow(recap),
      const SizedBox(height: 14),
      _newVsReturning(recap),
      const SizedBox(height: 14),
      _whenFansCommit(recap),
      const SizedBox(height: 14),
      _roomsThatDraw(recap),
      const SizedBox(height: 14),
      _bestNights(recap),
      const SizedBox(height: 14),
      _repeatFans(recap),
      ..._footnotes(recap),
    ];
  }

  Widget _loadingState() {
    return Text(
      'Loading fan analytics…',
      style: epText(size: 11.5, color: Ep.contentDisabled),
    );
  }

  Widget _errorState(AppState app, String bandId, String error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Couldn't load fan analytics. $error",
          style: epText(size: 11.5, color: Ep.contentDisabled, height: 1.45),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 140,
          child: EpButton(
            'RETRY',
            kind: EpButtonKind.outline,
            padding: const EdgeInsets.symmetric(vertical: 10),
            onTap: () => app.refreshBandRecap(bandId),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String bandName, {required bool hasOtherBands}) {
    final hint = hasOtherBands
        ? '\nTap the band name above to switch to another of your bands.'
        : '';
    return DashedBox(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Text(
        'No past gigs yet for ${bandName.toUpperCase()}. This recap fills '
        'in after its first show.$hint',
        textAlign: TextAlign.center,
        style: epText(size: 12, color: Ep.contentSecondary, height: 1.5),
      ),
    );
  }

  Widget _privacyNote() {
    return EpCard(
      variant: EpCardVariant.selected,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Text(
        'Aggregate data only. Any breakdown covering fewer than 5 fans is '
        'withheld entirely. No individual fan is ever identifiable.',
        style: epText(size: 11, color: Ep.contentPrimary, height: 1.45),
      ),
    );
  }

  Widget _headline(BandRecap recap) {
    return Row(
      children: [
        EpStatCard(
          label: 'SHOWS PLAYED',
          value: '${recap.totals.shows}',
          caption: 'in this recap',
        ),
        const SizedBox(width: 8),
        EpStatCard(
          label: 'TOTAL RSVPS',
          value: '${recap.totals.measuredRsvps}',
          caption: 'measured turnout',
        ),
        const SizedBox(width: 8),
        EpStatCard(
          label: 'AVG / SHOW',
          value: recap.totals.avgPerShow.toStringAsFixed(1),
          caption: 'across each show',
        ),
      ],
    );
  }

  Widget _turnoutByShow(BandRecap recap) {
    return _analyticsCard('TURNOUT BY SHOW', [
      for (final show in recap.shows) ...[
        EpBar(
          label: show.title,
          value: show.measuredRsvps,
          max: recap.totals.bestShowRsvps,
          valueText: '${show.measuredRsvps}',
        ),
        const SizedBox(height: 4),
        Text(
          '${Gig.dateShortFor(show.startsAt)} · ${show.venueName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: epText(size: 10.5, color: Ep.contentDisabled),
        ),
        const SizedBox(height: 13),
      ],
      Text(
        'avg ${recap.totals.avgPerShow.toStringAsFixed(1)} · '
        'best ${recap.totals.bestShowRsvps}',
        style: epText(size: 11, weight: FontWeight.w800, color: Ep.accent),
      ),
    ]);
  }

  Widget _newVsReturning(BandRecap recap) {
    return _analyticsCard('NEW VS RETURNING', [
      if (recap.newReturningSuppressed)
        const EpSuppressedNote()
      else
        for (final show in recap.shows)
          if (show.newFans != null && show.returningFans != null) ...[
            Text(
              show.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: epText(
                size: 11,
                weight: FontWeight.w800,
                color: Ep.contentSecondary,
              ),
            ),
            const SizedBox(height: 7),
            EpStackedBar(
              newValue: show.newFans!,
              returningValue: show.returningFans!,
              newLabel: 'NEW ${show.newFans}',
              returningLabel: 'RETURNING ${show.returningFans}',
            ),
            const SizedBox(height: 13),
          ],
      if (recap.window.truncated) ...[
        const SizedBox(height: 2),
        Text(
          '“New” means new within this analyzed window, not new-ever. The '
          'oldest analyzed show reads as 100% new because earlier shows '
          'were outside the measurement window.',
          style: epText(size: 10.5, color: Ep.contentDisabled, height: 1.45),
        ),
      ],
    ]);
  }

  Widget _whenFansCommit(BandRecap recap) {
    final leadTime = recap.leadTime;
    final maxCount = leadTime.buckets.fold<int>(
      0,
      (highest, bucket) => bucket.count > highest ? bucket.count : highest,
    );

    return _analyticsCard('WHEN FANS COMMIT', [
      if (leadTime.suppressed)
        const EpSuppressedNote()
      else ...[
        for (final bucket in leadTime.buckets) ...[
          EpBar(
            label: _leadTimeLabel(bucket.key),
            value: bucket.count,
            max: maxCount,
            valueText: '${bucket.count}',
          ),
          const SizedBox(height: 12),
        ],
        if (leadTime.medianDays != null)
          Text(
            'Median RSVP: ${_formatNumber(leadTime.medianDays!)} days '
            'before the show.',
            style: epText(size: 11, color: Ep.contentSecondary),
          ),
      ],
      if (leadTime.unmeasurable > 0) ...[
        const SizedBox(height: 12),
        Text(
          _unmeasurableLeadTimeNote(leadTime.unmeasurable),
          style: epText(size: 10.5, color: Ep.contentDisabled, height: 1.45),
        ),
      ],
    ]);
  }

  Widget _roomsThatDraw(BandRecap recap) {
    final maxAverage = recap.venues.rows.fold<num>(
      0,
      (highest, row) => row.avgRsvps > highest ? row.avgRsvps : highest,
    );

    return _analyticsCard('ROOMS THAT DRAW', [
      if (recap.venues.suppressed)
        const EpSuppressedNote()
      else
        for (final row in recap.venues.rows) ...[
          EpBar(
            label: row.venueName,
            value: row.avgRsvps,
            max: maxAverage,
            valueText: _formatNumber(row.avgRsvps),
          ),
          const SizedBox(height: 12),
        ],
    ]);
  }

  Widget _bestNights(BandRecap recap) {
    final maxAverage = recap.weekdays.rows.fold<num>(
      0,
      (highest, row) => row.avgRsvps > highest ? row.avgRsvps : highest,
    );

    return _analyticsCard('BEST NIGHTS', [
      if (recap.weekdays.suppressed)
        const EpSuppressedNote()
      else
        for (final row in recap.weekdays.rows) ...[
          EpBar(
            label: weekdayNamesUpper[row.weekday - 1],
            value: row.avgRsvps,
            max: maxAverage,
            valueText: _formatNumber(row.avgRsvps),
          ),
          const SizedBox(height: 12),
        ],
    ]);
  }

  Widget _repeatFans(BandRecap recap) {
    final maxCount = recap.repeatFans.tiers.fold<int>(
      0,
      (highest, tier) => tier.count > highest ? tier.count : highest,
    );

    return _analyticsCard('REPEAT FANS', [
      if (recap.repeatFans.suppressed)
        const EpSuppressedNote()
      else
        for (final tier in recap.repeatFans.tiers) ...[
          EpBar(
            label: _repeatFanLabel(tier.key),
            value: tier.count,
            max: maxCount,
            valueText: '${tier.count}',
          ),
          const SizedBox(height: 12),
        ],
    ]);
  }

  List<Widget> _footnotes(BandRecap recap) {
    final notes = <String>[
      if (recap.window.truncated)
        'Only the most recent shows are analyzed here; older shows exist '
            'outside this recap window.',
      if (recap.totals.reportedRsvps != recap.totals.measuredRsvps)
        'The RSVP totals above use measured RSVP records, so they may differ '
            'from the “going” count shown elsewhere in the app.',
    ];
    if (notes.isEmpty) return const <Widget>[];

    return [
      const SizedBox(height: 14),
      Text(
        notes.join('\n'),
        style: epText(size: 10.5, color: Ep.contentDisabled, height: 1.5),
      ),
    ];
  }

  Widget _analyticsCard(String title, List<Widget> children) {
    return EpCard(
      padding: const EdgeInsets.all(14),
      radius: 13,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(title),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  String _leadTimeLabel(String key) => switch (key) {
    'twoWeeksPlus' => '2+ weeks ahead',
    'oneToTwoWeeks' => '1–2 weeks',
    'underWeek' => 'under a week',
    'dayOf' => 'day of',
    _ => key,
  };

  String _repeatFanLabel(String key) => switch (key) {
    'one' => '1 show',
    'twoToThree' => '2–3 shows',
    'fourPlus' => '4+ shows',
    _ => key,
  };

  String _formatNumber(num value) {
    final decimal = value.toDouble();
    if (decimal == decimal.roundToDouble()) return decimal.toInt().toString();
    return decimal.toStringAsFixed(1);
  }

  String _unmeasurableLeadTimeNote(int count) {
    if (count == 1) {
      return '1 RSVP record was created after its show had already happened, '
          'so its lead time before the show is unknown.';
    }
    return '$count RSVP records were created after their shows had already '
        'happened, so their lead time before the shows is unknown.';
  }
}
