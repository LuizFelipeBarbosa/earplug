import 'dart:math' as math;

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
        _bandSelector(context, band),
        const SizedBox(height: 4),
        Text('FAN ANALYTICS', style: Theme.of(context).textTheme.epPageHeading),
        if (recap != null && recap.shows.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _windowLabel(recap),
            style: Theme.of(context).textTheme.epSection.copyWith(
              color: context.epColors.contentSecondary,
            ),
          ),
        ],
        const SizedBox(height: 14),
        ..._bodyFor(context, app, band, recap, error),
      ],
    );
  }

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
    BuildContext context,
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
      _bestShowTakeaway(recap),
      const SizedBox(height: 14),
      _headline(recap),
      const SizedBox(height: 14),
      _turnoutByShow(recap),
      const SizedBox(height: 14),
      _contextGrid(recap),
      const SizedBox(height: 14),
      _newVsReturning(context, recap),
      const SizedBox(height: 14),
      _whenFansCommit(context, recap),
      const SizedBox(height: 14),
      _roomsThatDraw(recap),
      const SizedBox(height: 14),
      _bestNights(recap),
      const SizedBox(height: 14),
      _repeatFans(recap),
      ..._footnotes(context, recap),
    ];
  }

  Widget _loadingState() {
    return Builder(
      builder: (context) => Text(
        'Loading fan analytics…',
        style: Theme.of(
          context,
        ).textTheme.epCaption.copyWith(color: context.epColors.contentDisabled),
      ),
    );
  }

  Widget _errorState(AppState app, String bandId, String error) {
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't load fan analytics. $error",
            style: Theme.of(context).textTheme.epCaption.copyWith(
              color: context.epColors.contentDisabled,
            ),
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
      ),
    );
  }

  Widget _emptyState(String bandName, {required bool hasOtherBands}) {
    final hint = hasOtherBands
        ? '\nTap the band name above to switch to another of your bands.'
        : '';
    return Builder(
      builder: (context) => DashedBox(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        child: Text(
          'No past gigs yet for ${bandName.toUpperCase()}. This recap fills '
          'in after its first show.$hint',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.contentSecondary),
        ),
      ),
    );
  }

  Widget _privacyNote() {
    return Builder(
      builder: (context) => EpCard(
        key: const Key('analytics-privacy-note'),
        variant: EpCardVariant.selected,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: context.epColors.volt, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'AGGREGATE ONLY · BREAKDOWNS UNDER 5 FANS WITHHELD\n'
                'No individual fan is ever identifiable.',
                style: Theme.of(context).textTheme.epCaption,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bestShowTakeaway(BandRecap recap) {
    final bestShows = _bestShows(recap);
    final best = bestShows.first;
    final kicker = bestShows.length == 1
        ? 'BEST SHOW THIS WINDOW'
        : 'BEST SHOW THIS WINDOW · ${bestShows.length}-WAY TIE';
    return VoltStrip(
      key: const Key('analytics-best-show'),
      kicker: kicker,
      title: best.title,
      meta: [
        if (best.venueName.trim().isNotEmpty) best.venueName,
        '${best.measuredRsvps} RSVPs',
        _performanceLabel(best.measuredRsvps, recap.totals.avgPerShow),
      ].join(' · '),
    );
  }

  Widget _headline(BandRecap recap) {
    return Row(
      children: [
        EpStatCard(
          label: 'SHOWS PLAYED',
          value: '${recap.totals.shows}',
          caption: 'this window',
        ),
        const SizedBox(width: 8),
        EpStatCard(
          label: 'TOTAL RSVPS',
          value: '${recap.totals.measuredRsvps}',
          caption: 'measured',
        ),
        const SizedBox(width: 8),
        EpStatCard(
          label: 'AVG / SHOW',
          value: recap.totals.avgPerShow.toStringAsFixed(1),
          caption: 'per night',
        ),
      ],
    );
  }

  Widget _turnoutByShow(BandRecap recap) {
    return _analyticsSection(
      key: const Key('analytics-turnout'),
      title: 'TURNOUT BY SHOW',
      child: _TurnoutChart(
        shows: _sortedShows(recap),
        average: recap.totals.avgPerShow,
      ),
    );
  }

  Widget _contextGrid(BandRecap recap) {
    final room = _topRoom(recap);
    final lead = _topLeadBucket(recap);
    final night = _topNight(recap);
    final repeatTotal = recap.repeatFans.tiers.fold<int>(
      0,
      (total, tier) => total + tier.count,
    );
    final repeatCount = recap.repeatFans.tiers
        .where((tier) => tier.key != 'one')
        .fold<int>(0, (total, tier) => total + tier.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionBar(
          label: 'AT A GLANCE',
          padding: EdgeInsets.only(bottom: 10),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ContextTile(
                label: 'TOP ROOM',
                value: recap.venues.suppressed
                    ? null
                    : room?.venueName ?? 'NO ROOM DATA',
                caption: room == null || recap.venues.suppressed
                    ? null
                    : '${_formatNumber(room.avgRsvps)} avg · '
                          '${room.shows} ${room.shows == 1 ? 'show' : 'shows'}',
                suppressed: recap.venues.suppressed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ContextTile(
                label: 'COMMIT WINDOW',
                value: recap.leadTime.suppressed
                    ? null
                    : lead == null
                    ? 'NO LEAD DATA'
                    : _leadTimeLabel(lead.key).toUpperCase(),
                caption: lead == null || recap.leadTime.suppressed
                    ? null
                    : '${lead.count} measured RSVPs',
                suppressed: recap.leadTime.suppressed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ContextTile(
                label: 'REPEAT FANS',
                value: recap.repeatFans.suppressed
                    ? null
                    : repeatTotal == 0
                    ? 'NO REPEAT DATA'
                    : '${(repeatCount / repeatTotal * 100).round()}%',
                caption: repeatTotal == 0 || recap.repeatFans.suppressed
                    ? null
                    : '$repeatCount of $repeatTotal returned',
                suppressed: recap.repeatFans.suppressed,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ContextTile(
                label: 'TOP NIGHT',
                value: recap.weekdays.suppressed
                    ? null
                    : night == null
                    ? 'NO NIGHT DATA'
                    : weekdayNamesUpper[night.weekday - 1],
                caption: night == null || recap.weekdays.suppressed
                    ? null
                    : '${_formatNumber(night.avgRsvps)} avg',
                suppressed: recap.weekdays.suppressed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _newVsReturning(BuildContext context, BandRecap recap) {
    return _analyticsSection(
      key: const Key('analytics-new-returning'),
      title: 'NEW VS RETURNING',
      child: recap.newReturningSuppressed
          ? const _SuppressedBreakdown()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final show in _sortedShows(recap))
                  if (show.newFans != null && show.returningFans != null) ...[
                    Text(
                      show.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: epText(
                        size: 11,
                        weight: FontWeight.w800,
                        color: context.epColors.contentSecondary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    _AnalyticsStackedBar(
                      newFans: show.newFans!,
                      returningFans: show.returningFans!,
                    ),
                    const SizedBox(height: 13),
                  ],
                if (recap.window.truncated)
                  Text(
                    '“New” means new within this analyzed window, not new-ever. '
                    'The oldest analyzed show reads as entirely new because '
                    'earlier shows were outside the measurement window.',
                    style: epText(
                      size: 11,
                      color: context.epColors.contentDisabled,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _whenFansCommit(BuildContext context, BandRecap recap) {
    final leadTime = recap.leadTime;
    final maxCount = leadTime.buckets.fold<int>(
      0,
      (highest, bucket) => math.max(highest, bucket.count),
    );

    return _analyticsSection(
      key: const Key('analytics-lead-time'),
      title: 'WHEN FANS COMMIT',
      child: leadTime.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                    style: epText(
                      size: 11,
                      color: context.epColors.contentSecondary,
                    ),
                  ),
                if (leadTime.unmeasurable > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    _unmeasurableLeadTimeNote(leadTime.unmeasurable),
                    style: epText(
                      size: 11,
                      color: context.epColors.contentDisabled,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _roomsThatDraw(BandRecap recap) {
    final maxAverage = recap.venues.rows.fold<num>(
      0,
      (highest, row) => math.max(highest, row.avgRsvps),
    );

    return _analyticsSection(
      key: const Key('analytics-rooms'),
      title: 'ROOMS THAT DRAW',
      child: recap.venues.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              children: [
                for (final row in recap.venues.rows) ...[
                  EpBar(
                    label: row.venueName,
                    value: row.avgRsvps,
                    max: maxAverage,
                    valueText: _formatNumber(row.avgRsvps),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Widget _bestNights(BandRecap recap) {
    final maxAverage = recap.weekdays.rows.fold<num>(
      0,
      (highest, row) => math.max(highest, row.avgRsvps),
    );

    return _analyticsSection(
      key: const Key('analytics-best-nights'),
      title: 'BEST NIGHTS',
      child: recap.weekdays.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              children: [
                for (final row in recap.weekdays.rows) ...[
                  EpBar(
                    label: weekdayNamesUpper[row.weekday - 1],
                    value: row.avgRsvps,
                    max: maxAverage,
                    valueText: _formatNumber(row.avgRsvps),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  Widget _repeatFans(BandRecap recap) {
    final maxCount = recap.repeatFans.tiers.fold<int>(
      0,
      (highest, tier) => math.max(highest, tier.count),
    );

    return _analyticsSection(
      key: const Key('analytics-repeat-fans'),
      title: 'REPEAT FANS',
      child: recap.repeatFans.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              children: [
                for (final tier in recap.repeatFans.tiers) ...[
                  EpBar(
                    label: _repeatFanLabel(tier.key),
                    value: tier.count,
                    max: maxCount,
                    valueText: '${tier.count}',
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  List<Widget> _footnotes(BuildContext context, BandRecap recap) {
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
        style: epText(
          size: 11,
          color: context.epColors.contentDisabled,
          height: 1.5,
        ),
      ),
    ];
  }

  Widget _analyticsSection({
    required Key key,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return EpCard(
      key: key,
      variant: EpCardVariant.raised,
      padding: const EdgeInsets.all(14),
      radius: 13,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionBar(
            label: title,
            trailing: trailing,
            padding: const EdgeInsets.only(bottom: 12),
          ),
          child,
        ],
      ),
    );
  }

  static List<RecapShow> _sortedShows(BandRecap recap) {
    final shows = [...recap.shows]
      ..sort((a, b) {
        final byDate = b.startsAt.compareTo(a.startsAt);
        return byDate != 0 ? byDate : a.gigId.compareTo(b.gigId);
      });
    return shows;
  }

  static List<RecapShow> _bestShows(BandRecap recap) {
    final shows = _sortedShows(recap);
    final best = shows.fold<int>(
      0,
      (highest, show) => math.max(highest, show.measuredRsvps),
    );
    return shows.where((show) => show.measuredRsvps == best).toList();
  }

  static RecapVenue? _topRoom(BandRecap recap) {
    if (recap.venues.rows.isEmpty) return null;
    final rows = [...recap.venues.rows]
      ..sort((a, b) {
        final byAverage = b.avgRsvps.compareTo(a.avgRsvps);
        return byAverage != 0 ? byAverage : a.venueName.compareTo(b.venueName);
      });
    return rows.first;
  }

  static RecapBucket? _topLeadBucket(BandRecap recap) {
    if (recap.leadTime.buckets.isEmpty) return null;
    final rows = [...recap.leadTime.buckets]
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return rows.first;
  }

  static RecapWeekday? _topNight(BandRecap recap) {
    if (recap.weekdays.rows.isEmpty) return null;
    final rows = [...recap.weekdays.rows]
      ..sort((a, b) {
        final byAverage = b.avgRsvps.compareTo(a.avgRsvps);
        return byAverage != 0 ? byAverage : a.weekday.compareTo(b.weekday);
      });
    return rows.first;
  }

  static String _performanceLabel(num best, num average) {
    if (average <= 0) {
      return best <= 0 ? 'at window average' : 'above a zero average';
    }
    final percent = ((best - average) / average * 100).round();
    if (percent <= 0) return 'at window average';
    return '$percent% above avg';
  }

  static String _windowLabel(BandRecap recap) {
    final first = recap.window.firstStartsAt;
    final last = recap.window.lastStartsAt;
    final prefix = 'LAST ${recap.window.showsAnalyzed} SHOWS';
    if (first == null || last == null) return prefix;
    final firstDate = DateTime.fromMillisecondsSinceEpoch(first);
    final lastDate = DateTime.fromMillisecondsSinceEpoch(last);
    return '$prefix · ${monthNamesUpper[firstDate.month - 1]} – '
        '${monthNamesUpper[lastDate.month - 1]}';
  }

  static String _leadTimeLabel(String key) => switch (key) {
    'twoWeeksPlus' => '2+ weeks ahead',
    'oneToTwoWeeks' => '1–2 weeks',
    'underWeek' => 'under a week',
    'dayOf' => 'day of',
    _ => key,
  };

  static String _repeatFanLabel(String key) => switch (key) {
    'one' => '1 show',
    'twoToThree' => '2–3 shows',
    'fourPlus' => '4+ shows',
    _ => key,
  };

  static String _formatNumber(num value) {
    final decimal = value.toDouble();
    if (decimal == decimal.roundToDouble()) return decimal.toInt().toString();
    return decimal.toStringAsFixed(1);
  }

  static String _unmeasurableLeadTimeNote(int count) {
    if (count == 1) {
      return '1 RSVP record was created after its show had already happened, '
          'so its lead time before the show is unknown.';
    }
    return '$count RSVP records were created after their shows had already '
        'happened, so their lead time before the shows is unknown.';
  }
}

class _TurnoutChart extends StatelessWidget {
  const _TurnoutChart({required this.shows, required this.average});

  final List<RecapShow> shows;
  final num average;

  @override
  Widget build(BuildContext context) {
    final maxValue = shows.fold<num>(
      0,
      (highest, show) => math.max(highest, show.measuredRsvps),
    );
    final scale = math.max<num>(1, math.max(maxValue, average));
    const plotHeight = 142.0;
    double barHeightFor(num value) =>
        ((value / scale).clamp(0, 1) * (plotHeight - 40)).toDouble();
    final averageTop = plotHeight - barHeightFor(average);

    return SizedBox(
      height: 210,
      child: Stack(
        children: [
          Positioned(
            top: averageTop,
            left: 0,
            right: 0,
            child: Row(
              children: [
                Expanded(child: Divider(color: context.epColors.accent)),
                const SizedBox(width: 6),
                Text(
                  'AVG ${AnalyticsScreen._formatNumber(average)}',
                  style: Theme.of(
                    context,
                  ).textTheme.epMeta.copyWith(color: context.epColors.accent),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final show in shows)
                  Expanded(
                    child: Semantics(
                      label:
                          '${show.title}, ${show.measuredRsvps} measured '
                          'RSVPs, ${Gig.dateShortFor(show.startsAt)}, '
                          '${show.venueName}',
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            children: [
                              SizedBox(
                                height: plotHeight,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${show.measuredRsvps}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .epMeta
                                            .copyWith(
                                              color: context
                                                  .epColors
                                                  .contentPrimary,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Container(
                                        width: 24,
                                        height: barHeightFor(
                                          show.measuredRsvps,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Ep.brand,
                                          borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                show.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.epMeta,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsStackedBar extends StatelessWidget {
  const _AnalyticsStackedBar({
    required this.newFans,
    required this.returningFans,
  });

  final int newFans;
  final int returningFans;

  @override
  Widget build(BuildContext context) {
    final total = math.max(0, newFans) + math.max(0, returningFans);
    final newFlex = total == 0
        ? 0
        : math.max(1, (newFans / total * 1000).round());
    final returningFlex = total == 0
        ? 0
        : math.max(1, (returningFans / total * 1000).round());
    return Semantics(
      label: '$newFans new fans and $returningFans returning fans',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.epColors.surfaceDisabled,
              border: Border.all(color: context.epColors.border),
              borderRadius: BorderRadius.circular(99),
            ),
            child: total == 0
                ? null
                : Row(
                    children: [
                      if (newFans > 0)
                        Expanded(
                          flex: newFlex,
                          child: const ColoredBox(color: Ep.brand),
                        ),
                      if (returningFans > 0)
                        Expanded(
                          flex: returningFlex,
                          child: ColoredBox(color: context.epColors.accent),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _ChartLegend(color: Ep.brand, label: 'NEW $newFans'),
              _ChartLegend(
                color: context.epColors.accent,
                label: 'RETURNING $returningFans',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.epCaption),
      ],
    );
  }
}

class _ContextTile extends StatelessWidget {
  const _ContextTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.suppressed,
  });

  final String label;
  final String? value;
  final String? caption;
  final bool suppressed;

  @override
  Widget build(BuildContext context) {
    return EpCard(
      variant: suppressed ? EpCardVariant.disabled : EpCardVariant.raised,
      padding: const EdgeInsets.all(12),
      radius: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 92),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.epChipLabel.copyWith(
                color: context.epColors.contentSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (suppressed) ...[
              Text(
                'SUPPRESSED',
                style: Theme.of(context).textTheme.epSectionHeading.copyWith(
                  color: context.epColors.contentDisabled,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Withheld · under five fans',
                style: Theme.of(context).textTheme.epCaption,
              ),
            ] else ...[
              Text(
                value!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.epSectionHeading.copyWith(fontSize: 16),
              ),
              if (caption != null) ...[
                const SizedBox(height: 4),
                Text(caption!, style: Theme.of(context).textTheme.epCaption),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SuppressedBreakdown extends StatelessWidget {
  const _SuppressedBreakdown();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Suppressed. Not enough data to show this breakdown.',
      excludeSemantics: true,
      child: DashedBox(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SUPPRESSED',
              style: Theme.of(context).textTheme.epChipLabel.copyWith(
                color: context.epColors.contentDisabled,
              ),
            ),
            const SizedBox(height: 4),
            const EpSuppressedNote(),
          ],
        ),
      ),
    );
  }
}
