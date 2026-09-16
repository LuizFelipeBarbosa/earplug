import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../date_names.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_rows.dart';
import '../widgets/ep_text.dart';
import '../widgets/sheets.dart';
import 'analytics_sheets.dart';

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
        EpLayout.gutter,
        headerTopPad(context),
        EpLayout.gutter,
        0,
      ),
      children: [
        EpEyebrow.accent(
          recap != null && recap.shows.isNotEmpty
              ? '${band.name} · ${recapWindowLabel(recap)}'
              : band.name,
        ),
        const SizedBox(height: 12),
        const EpDisplay('Fan\ninsights'),
        if (recap != null && recap.shows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Aggregate only. Breakdowns under 5 fans are withheld; '
            'no individual fan is identifiable.',
            key: const Key('analytics-privacy-note'),
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: EpPill(
            label: band.name,
            icon: Icons.arrow_drop_down,
            onPressed: () => showSwitcherSheet(context),
          ),
        ),
        const SizedBox(height: 24),
        ..._bodyFor(context, app, band, recap, error),
        const SizedBox(height: tabBarClearance),
      ],
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
      if (error == null) {
        return [
          EpMonoText('Loading fan analytics…', color: context.epColors.muted),
        ];
      }
      return [
        Text(
          "Couldn't load fan analytics. $error",
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: EpPill(
            label: 'Retry',
            onPressed: () => app.refreshBandRecap(band.id),
          ),
        ),
      ];
    }
    if (recap.shows.isEmpty) {
      final hint = app.myBands.length > 1
          ? '\nTap the band name above to switch to another of your bands.'
          : '';
      return [
        const EpHairline(),
        const SizedBox(height: 16),
        Text(
          'No past gigs yet for ${band.name}. This recap fills '
          'in after its first show.$hint',
          style: Theme.of(
            context,
          ).textTheme.epBody.copyWith(color: context.epColors.muted),
        ),
      ];
    }

    return [
      EpStatGrid(
        stats: [
          EpStat('${recap.totals.shows}', 'Shows'),
          EpStat('${recap.totals.measuredRsvps}', 'RSVPs'),
          EpStat(recapFormatNumber(recap.totals.avgPerShow), 'Avg / show'),
        ],
      ),
      const SizedBox(height: 24),
      _bestShowTakeaway(recap),
      const SizedBox(height: 28),
      _turnoutByShow(context, recap),
      const SizedBox(height: 24),
      const EpHairline(),
      _contextGrid(recap),
      const SizedBox(height: 24),
      _TicketsAndCheckInsSection(bandId: band.id),
      const SizedBox(height: 24),
      _newVsReturning(context, recap),
      const SizedBox(height: 24),
      _whenFansCommit(recap),
      const SizedBox(height: 24),
      _roomsThatDraw(context, recap),
      const SizedBox(height: 24),
      _bestNights(context, recap),
      const SizedBox(height: 24),
      _repeatFans(recap),
      ..._footnotes(context, recap),
    ];
  }

  Widget _bestShowTakeaway(BandRecap recap) {
    final bestShows = _bestShows(recap);
    final best = bestShows.first;
    return Column(
      key: const Key('analytics-best-show'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpEyebrow(
          'Best show · '
          '${_performanceLabel(best.measuredRsvps, recap.totals.avgPerShow)}',
        ),
        const SizedBox(height: 4),
        EpDisplay(
          [
            best.title,
            if (best.venueName.trim().isNotEmpty) best.venueName,
            '${best.measuredRsvps} RSVPs',
          ].join(' · '),
          size: 24,
        ),
        if (bestShows.length > 1) ...[
          const SizedBox(height: 8),
          EpEyebrow('${bestShows.length}-way tie'),
        ],
      ],
    );
  }

  Widget _turnoutByShow(BuildContext context, BandRecap recap) {
    final shows = recapSortedShows(recap);
    return _analyticsSection(
      key: const Key('analytics-turnout'),
      title: 'Check-ins by show',
      trailing: shows.length > kRecapPreviewCount
          ? SectionActionButton(
              key: const Key('analytics-turnout-see-all'),
              label: 'SEE ALL ${shows.length}',
              onPressed: () => showRecapShowsSheet(context, recap),
            )
          : null,
      child: _TurnoutChart(
        shows: shows.take(kRecapPreviewCount).toList(),
        average: recap.totals.avgPerShow,
        bestShowId: _bestShows(recap).first.gigId,
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

    return EpFactGrid(
      bottomLine: false,
      cells: [
        _RecapFact(
          label: 'Top room',
          value: room?.venueName ?? 'No room data',
          sub: room == null
              ? null
              : '${recapFormatNumber(room.avgRsvps)} avg · '
                    '${room.shows} ${room.shows == 1 ? 'show' : 'shows'}',
          suppressed: recap.venues.suppressed,
        ),
        _RecapFact(
          label: 'Commit window',
          value: lead == null ? 'No lead data' : _leadTimeLabel(lead.key),
          sub: lead == null ? null : '${lead.count} measured RSVPs',
          suppressed: recap.leadTime.suppressed,
        ),
        _RecapFact(
          label: 'Repeat fans',
          value: repeatTotal == 0
              ? 'No repeat data'
              : '${(repeatCount / repeatTotal * 100).round()}%',
          sub: repeatTotal == 0
              ? null
              : '$repeatCount of $repeatTotal returned',
          suppressed: recap.repeatFans.suppressed,
        ),
        _RecapFact(
          label: 'Top night',
          value: night == null
              ? 'No night data'
              : weekdayNames[night.weekday - 1],
          sub: night == null
              ? null
              : '${recapFormatNumber(night.avgRsvps)} avg',
          suppressed: recap.weekdays.suppressed,
        ),
      ],
    );
  }

  Widget _newVsReturning(BuildContext context, BandRecap recap) {
    final shows = recapSortedShows(recap)
        .where((show) => show.newFans != null && show.returningFans != null)
        .toList();
    return _analyticsSection(
      key: const Key('analytics-new-returning'),
      title: 'New vs returning',
      trailing:
          !recap.newReturningSuppressed &&
              recap.shows.length > kRecapPreviewCount
          ? SectionActionButton(
              key: const Key('analytics-new-returning-see-all'),
              label: 'SEE ALL ${recap.shows.length}',
              onPressed: () => showRecapShowsSheet(context, recap),
            )
          : null,
      child: recap.newReturningSuppressed
          ? const _SuppressedBreakdown()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final show in shows.take(kRecapPreviewCount)) ...[
                  LedgerRow(title: show.title),
                  const SizedBox(height: 8),
                  AnalyticsStackedBar(
                    newFans: show.newFans!,
                    returningFans: show.returningFans!,
                  ),
                  const SizedBox(height: 16),
                ],
                if (recap.window.truncated)
                  EpMonoText(
                    '“New” means new within this analyzed window, not new-ever. '
                    'The oldest analyzed show reads as entirely new because '
                    'earlier shows were outside the measurement window.',
                    color: context.epColors.muted,
                  ),
              ],
            ),
    );
  }

  Widget _whenFansCommit(BandRecap recap) {
    final leadTime = recap.leadTime;
    final maxCount = leadTime.buckets.fold<int>(
      0,
      (highest, bucket) => math.max(highest, bucket.count),
    );

    return _analyticsSection(
      key: const Key('analytics-lead-time'),
      title: 'When fans commit',
      child: leadTime.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final bucket in leadTime.buckets)
                  EpBar(
                    label: _leadTimeLabel(bucket.key),
                    value: bucket.count,
                    max: maxCount,
                    valueText: '${bucket.count}',
                  ),
                if (leadTime.medianDays != null)
                  LedgerRow(
                    title:
                        'Median RSVP: ${recapFormatNumber(leadTime.medianDays!)} '
                        'days before the show.',
                  ),
                if (leadTime.unmeasurable > 0)
                  LedgerRow(
                    title: _unmeasurableLeadTimeNote(leadTime.unmeasurable),
                  ),
              ],
            ),
    );
  }

  Widget _roomsThatDraw(BuildContext context, BandRecap recap) {
    final rows = recapSortedVenues(recap);
    final maxAverage = rows.fold<num>(
      0,
      (highest, row) => math.max(highest, row.avgRsvps),
    );

    return _analyticsSection(
      key: const Key('analytics-rooms'),
      title: 'Rooms that draw',
      trailing: !recap.venues.suppressed && rows.length > kRecapPreviewCount
          ? SectionActionButton(
              key: const Key('analytics-rooms-see-all'),
              label: 'SEE ALL ${rows.length}',
              onPressed: () => showRecapRowsSheet(
                context,
                title: 'ALL ${rows.length} ROOMS',
                subtitle: recapWindowLabel(recap),
                rows: [
                  for (final row in rows)
                    RecapDetailRow(
                      label: row.venueName,
                      meta:
                          '${row.shows} ${row.shows == 1 ? 'show' : 'shows'} · '
                          '${row.totalRsvps} total RSVPs',
                      value: row.avgRsvps,
                      valueText: '${recapFormatNumber(row.avgRsvps)} avg',
                    ),
                ],
              ),
            )
          : null,
      child: recap.venues.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              children: [
                for (final row in rows.take(kRecapPreviewCount))
                  EpBar(
                    label: row.venueName,
                    value: row.avgRsvps,
                    max: maxAverage,
                    valueText: recapFormatNumber(row.avgRsvps),
                  ),
              ],
            ),
    );
  }

  Widget _bestNights(BuildContext context, BandRecap recap) {
    final rows = recapSortedWeekdays(recap);
    final maxAverage = rows.fold<num>(
      0,
      (highest, row) => math.max(highest, row.avgRsvps),
    );

    return _analyticsSection(
      key: const Key('analytics-best-nights'),
      title: 'Best nights',
      trailing: !recap.weekdays.suppressed && rows.length > kRecapPreviewCount
          ? SectionActionButton(
              key: const Key('analytics-best-nights-see-all'),
              label: 'SEE ALL ${rows.length}',
              onPressed: () => showRecapRowsSheet(
                context,
                title: 'ALL ${rows.length} NIGHTS',
                subtitle: recapWindowLabel(recap),
                rows: [
                  for (final row in rows)
                    RecapDetailRow(
                      label: weekdayNamesUpper[row.weekday - 1],
                      meta: '${row.shows} ${row.shows == 1 ? 'show' : 'shows'}',
                      value: row.avgRsvps,
                      valueText: '${recapFormatNumber(row.avgRsvps)} avg',
                    ),
                ],
              ),
            )
          : null,
      child: recap.weekdays.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              children: [
                for (final row in rows.take(kRecapPreviewCount))
                  EpBar(
                    label: weekdayNames[row.weekday - 1],
                    value: row.avgRsvps,
                    max: maxAverage,
                    valueText: recapFormatNumber(row.avgRsvps),
                  ),
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
      title: 'Repeat fans',
      child: recap.repeatFans.suppressed
          ? const _SuppressedBreakdown()
          : Column(
              children: [
                for (final tier in recap.repeatFans.tiers)
                  EpBar(
                    label: _repeatFanLabel(tier.key),
                    value: tier.count,
                    max: maxCount,
                    valueText: '${tier.count}',
                  ),
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
      const SizedBox(height: 24),
      EpMonoText(notes.join('\n'), color: context.epColors.muted),
    ];
  }

  static List<RecapShow> _bestShows(BandRecap recap) {
    final shows = recapSortedShows(recap);
    final best = shows.fold<int>(
      0,
      (highest, show) => math.max(highest, show.measuredRsvps),
    );
    return shows.where((show) => show.measuredRsvps == best).toList();
  }

  static RecapVenue? _topRoom(BandRecap recap) {
    final rooms = recapSortedVenues(recap);
    return rooms.isEmpty ? null : rooms.first;
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
    final nights = recapSortedWeekdays(recap);
    return nights.isEmpty ? null : nights.first;
  }

  static String _performanceLabel(num best, num average) {
    if (average <= 0) {
      return best <= 0 ? 'at window average' : 'above a zero average';
    }
    final percent = ((best - average) / average * 100).round();
    if (percent <= 0) return 'at window average';
    return '$percent% above average';
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

  static String _unmeasurableLeadTimeNote(int count) {
    if (count == 1) {
      return '1 RSVP record was created after its show had already happened, '
          'so its lead time before the show is unknown.';
    }
    return '$count RSVP records were created after their shows had already '
        'happened, so their lead time before the shows is unknown.';
  }
}

Widget _analyticsSection({
  required Key key,
  required String title,
  required Widget child,
  Widget? trailing,
}) {
  return Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionBar(
        label: title,
        trailing: trailing,
        padding: const EdgeInsets.only(bottom: 16),
      ),
      child,
    ],
  );
}

class _TicketsAndCheckInsSection extends StatefulWidget {
  const _TicketsAndCheckInsSection({required this.bandId});

  final String bandId;

  @override
  State<_TicketsAndCheckInsSection> createState() =>
      _TicketsAndCheckInsSectionState();
}

class _TicketsAndCheckInsSectionState
    extends State<_TicketsAndCheckInsSection> {
  @override
  void initState() {
    super.initState();
    unawaited(context.read<AppState>().loadMyBandInsights(widget.bandId));
  }

  @override
  void didUpdateWidget(covariant _TicketsAndCheckInsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bandId != widget.bandId) {
      unawaited(context.read<AppState>().loadMyBandInsights(widget.bandId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final insights = context.watch<AppState>().bandInsights(widget.bandId);
    final maxEvents =
        insights?.byPriceBand.buckets.fold<int>(
          0,
          (highest, bucket) => math.max(highest, bucket.events),
        ) ??
        0;

    return _analyticsSection(
      key: const Key('analytics-tickets'),
      title: 'TICKETS & CHECK-INS',
      child: insights == null
          ? const Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EpFactGrid(
                  cells: [
                    EpFactCell(
                      label: 'Tickets sold',
                      value: '${insights.ticketsSold}',
                    ),
                    EpFactCell(
                      label: 'Check-ins',
                      value: '${insights.checkIns}',
                    ),
                  ],
                ),
                if (insights.returningSuppressed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: EpMonoText(
                      'Returning attendees: not enough data',
                      color: context.epColors.muted,
                    ),
                  )
                else
                  LedgerRow(
                    title:
                        'Returning attendees: ${insights.returningAttendees}',
                  ),
                LedgerRow(title: _estimatedDrawLabel(insights.estimatedDraw)),
                const SizedBox(height: 12),
                if (insights.byPriceBand.suppressed)
                  const _SuppressedBreakdown()
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, bucket)
                          in insights.byPriceBand.buckets.indexed) ...[
                        if (i > 0) const SizedBox(height: 12),
                        EpBar(
                          label: _priceBandLabel(bucket.key),
                          value: bucket.events,
                          max: maxEvents,
                          valueText: '${bucket.events}',
                        ),
                      ],
                    ],
                  ),
                if (!insights.attribution.suppressed) ...[
                  const SizedBox(height: 10),
                  LedgerRow(
                    title:
                        'Ticket buyers: referral ${insights.attribution.referral} · '
                        'followers ${insights.attribution.follow} · '
                        'other ${insights.attribution.unattributed}',
                  ),
                ],
              ],
            ),
    );
  }
}

String _estimatedDrawLabel(EstimatedDraw? draw) {
  if (draw == null) return 'Estimated draw: No history yet';
  final basis = draw.basis == DrawBasis.checkIns ? 'check-ins' : 'RSVPs';
  return 'Estimated draw: ${draw.low}–${draw.high} · '
      '${draw.confidence.wireValue} confidence · based on $basis';
}

String _priceBandLabel(String key) => switch (key) {
  'free' => 'FREE',
  'under20' => r'UNDER $20',
  '20Plus' => r'$20+',
  _ => key,
};

class _TurnoutChart extends StatelessWidget {
  const _TurnoutChart({
    required this.shows,
    required this.average,
    required this.bestShowId,
  });

  final List<RecapShow> shows;
  final num average;
  final String bestShowId;

  @override
  Widget build(BuildContext context) {
    final maxValue = shows.fold<num>(
      0,
      (highest, show) => math.max(highest, show.measuredRsvps),
    );
    final scale = math.max<num>(1, math.max(maxValue, average));
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    // Keep the value labels above the tallest bar, including at large text.
    final plotHeight = 100 + 40 * textScale;
    double barHeightFor(num value) =>
        ((value / scale).clamp(0, 1) * 100).toDouble();
    final averageTop = plotHeight - barHeightFor(average);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 190),
      child: Stack(
        children: [
          Positioned(
            top: averageTop,
            left: 0,
            right: 0,
            child: CustomPaint(
              key: const Key('analytics-average-line'),
              size: const Size(double.infinity, 1),
              painter: _AverageLinePainter(context.epColors.outline),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final show in shows)
                Expanded(
                  child: Semantics(
                    label:
                        '${show.title}, ${show.measuredRsvps} measured '
                        'RSVPs, ${Gig.dateShortFor(show.startsAt)}, '
                        '${show.venueName}',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: plotHeight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                EpMonoText('${show.measuredRsvps}'),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  height: barHeightFor(show.measuredRsvps),
                                  color: show.gigId == bestShowId
                                      ? context.epColors.accent
                                      : context.epColors.panel,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          DefaultTextStyle.merge(
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            child: EpMonoText(
                              show.title,
                              size: 9,
                              color: context.epColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // The average caption has its own lane so it never covers a bar.
              SizedBox(width: 60 * textScale),
            ],
          ),
          Positioned(
            top: averageTop,
            right: 0,
            child: FractionalTranslation(
              translation: const Offset(0, -.5),
              child: ColoredBox(
                color: context.epColors.background,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: EpEyebrow('Avg ${recapFormatNumber(average)}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AverageLinePainter extends CustomPainter {
  const _AverageLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, .5),
        Offset(math.min(x + 4, size.width), .5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_AverageLinePainter oldDelegate) =>
      color != oldDelegate.color;
}

class _RecapFact extends StatelessWidget {
  const _RecapFact({
    required this.label,
    required this.value,
    required this.sub,
    required this.suppressed,
  });

  final String label;
  final String value;
  final String? sub;
  final bool suppressed;

  @override
  Widget build(BuildContext context) {
    if (!suppressed) return EpFactCell(label: label, value: value, sub: sub);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpEyebrow(label),
        const SizedBox(height: 8),
        EpMonoText('Withheld · under five fans', color: context.epColors.muted),
      ],
    );
  }
}

class _SuppressedBreakdown extends StatelessWidget {
  const _SuppressedBreakdown();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Suppressed. Not enough data to show this breakdown.',
    excludeSemantics: true,
    child: EpMonoText(
      'Withheld · Not enough data yet',
      color: context.epColors.muted,
    ),
  );
}

/// Labeled horizontal value bar scaled against a caller-supplied maximum.
class EpBar extends StatelessWidget {
  const EpBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.valueText,
  });

  final String label;
  final num value;
  final num max;
  final String valueText;

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0
        ? 0.0
        : (value.toDouble() / max.toDouble()).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerRow(title: label, details: [valueText]),
        Container(
          height: 3,
          color: context.epColors.panel,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: ColoredBox(color: context.epColors.ink),
          ),
        ),
      ],
    );
  }
}
