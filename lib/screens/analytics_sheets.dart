import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../date_names.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
import '../widgets/ep_text.dart';
import '../widgets/sheets.dart';

const int kRecapPreviewCount = 5;

List<RecapShow> recapSortedShows(BandRecap recap) {
  final shows = [...recap.shows]
    ..sort((a, b) {
      final byDate = b.startsAt.compareTo(a.startsAt);
      return byDate != 0 ? byDate : a.gigId.compareTo(b.gigId);
    });
  return shows;
}

List<RecapVenue> recapSortedVenues(BandRecap recap) {
  final venues = [...recap.venues.rows]
    ..sort((a, b) {
      final byAverage = b.avgRsvps.compareTo(a.avgRsvps);
      return byAverage != 0 ? byAverage : a.venueName.compareTo(b.venueName);
    });
  return venues;
}

List<RecapWeekday> recapSortedWeekdays(BandRecap recap) {
  final weekdays = [...recap.weekdays.rows]
    ..sort((a, b) {
      final byAverage = b.avgRsvps.compareTo(a.avgRsvps);
      return byAverage != 0 ? byAverage : a.weekday.compareTo(b.weekday);
    });
  return weekdays;
}

String recapFormatNumber(num value) {
  final decimal = value.toDouble();
  if (decimal == decimal.roundToDouble()) return decimal.toInt().toString();
  return decimal.toStringAsFixed(1);
}

String recapWindowLabel(BandRecap recap) {
  final first = recap.window.firstStartsAt;
  final last = recap.window.lastStartsAt;
  final prefix = 'Last ${recap.window.showsAnalyzed} shows';
  if (first == null || last == null) return prefix;
  final firstDate = DateTime.fromMillisecondsSinceEpoch(first);
  final lastDate = DateTime.fromMillisecondsSinceEpoch(last);
  return '$prefix · ${monthNames[firstDate.month - 1]} ${firstDate.day} – '
      '${monthNames[lastDate.month - 1]} ${lastDate.day}';
}

String recapVsAverageLabel(num value, num average) {
  if (average <= 0) return value > 0 ? 'above avg' : 'at avg';
  if (value == average) return 'at avg';

  final percent = ((value - average) / average * 100).round().abs();
  return value > average ? '+$percent% vs avg' : '-$percent% vs avg';
}

Future<void> showRecapShowsSheet(BuildContext context, BandRecap recap) {
  final shows = recapSortedShows(recap);
  final maxRsvps = shows.fold<num>(
    0,
    (highest, show) => math.max(highest, show.measuredRsvps),
  );
  final averageFraction = maxRsvps <= 0
      ? 0.0
      : (recap.totals.avgPerShow / maxRsvps).clamp(0.0, 1.0).toDouble();

  return showEpSheet(
    context,
    (ctx) => KeyedSubtree(
      key: const Key('analytics-shows-sheet'),
      child: EpSheetShell(
        padding: const EdgeInsets.fromLTRB(
          EpLayout.gutter,
          20,
          EpLayout.gutter,
          24,
        ),
        maxHeightFactor: .88,
        scrollable: true,
        mainAxisSize: MainAxisSize.min,
        header: EpDisplay('All ${recap.shows.length} shows', size: 28),
        children: [
          const SizedBox(height: 12),
          EpEyebrow(recapWindowLabel(recap)),
          const SizedBox(height: 8),
          EpEyebrow(
            'Avg ${recapFormatNumber(recap.totals.avgPerShow)} per show',
          ),
          if (recap.window.truncated) ...[
            const SizedBox(height: 5),
            Text(
              'Only the ${recap.window.showsAnalyzed} most recent shows are '
              'analyzed.',
              style: Theme.of(
                ctx,
              ).textTheme.epCaption.copyWith(color: ctx.epColors.muted),
            ),
          ],
          const SizedBox(height: 16),
          const EpHairline(),
          for (var index = 0; index < shows.length; index++) ...[
            _ShowDetailRow(
              show: shows[index],
              average: recap.totals.avgPerShow,
              maxRsvps: maxRsvps,
              averageFraction: averageFraction,
              showNewReturning: !recap.newReturningSuppressed,
            ),
          ],
        ],
      ),
    ),
  );
}

class RecapDetailRow {
  const RecapDetailRow({
    required this.label,
    required this.meta,
    required this.value,
    required this.valueText,
  });

  final String label;
  final String meta;
  final num value;
  final String valueText;
}

Future<void> showRecapRowsSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<RecapDetailRow> rows,
}) {
  final maxValue = rows.fold<num>(
    0,
    (highest, row) => math.max(highest, row.value),
  );

  return showEpSheet(
    context,
    (ctx) => KeyedSubtree(
      key: const Key('analytics-rows-sheet'),
      child: EpSheetShell(
        padding: const EdgeInsets.fromLTRB(
          EpLayout.gutter,
          20,
          EpLayout.gutter,
          24,
        ),
        maxHeightFactor: .88,
        scrollable: true,
        mainAxisSize: MainAxisSize.min,
        header: EpDisplay(title, size: 28),
        children: [
          const SizedBox(height: 12),
          EpEyebrow(subtitle),
          const SizedBox(height: 16),
          const EpHairline(),
          for (var index = 0; index < rows.length; index++) ...[
            _RecapDetailRow(row: rows[index], maxValue: maxValue),
          ],
        ],
      ),
    ),
  );
}

class AnalyticsStackedBar extends StatelessWidget {
  const AnalyticsStackedBar({
    super.key,
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
            decoration: BoxDecoration(color: context.epColors.panel),
            child: total == 0
                ? null
                : Row(
                    children: [
                      if (newFans > 0)
                        Expanded(
                          flex: newFlex,
                          child: ColoredBox(color: context.epColors.ink),
                        ),
                      if (returningFans > 0)
                        Expanded(
                          flex: returningFlex,
                          child: ColoredBox(color: context.epColors.outline),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _ChartLegend(color: context.epColors.ink, label: 'New $newFans'),
              _ChartLegend(
                color: context.epColors.outline,
                label: 'Returning $returningFans',
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
        Container(width: 7, height: 7, color: color),
        const SizedBox(width: 5),
        Flexible(child: EpMonoText(label, color: context.epColors.muted)),
      ],
    );
  }
}

class _ShowDetailRow extends StatelessWidget {
  const _ShowDetailRow({
    required this.show,
    required this.average,
    required this.maxRsvps,
    required this.averageFraction,
    required this.showNewReturning,
  });

  final RecapShow show;
  final num average;
  final num maxRsvps;
  final double averageFraction;
  final bool showNewReturning;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(show.startsAt);
    final fraction = maxRsvps <= 0
        ? 0.0
        : (show.measuredRsvps / maxRsvps).clamp(0.0, 1.0).toDouble();
    final hasNewReturning =
        showNewReturning && show.newFans != null && show.returningFans != null;
    final newReturningLabel = hasNewReturning
        ? ', ${show.newFans} new fans and ${show.returningFans} returning fans'
        : '';

    return Semantics(
      label:
          '${show.title}, ${show.measuredRsvps} measured RSVPs, '
          '${Gig.dateShortFor(show.startsAt)}, ${show.venueName}'
          '$newReturningLabel',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LedgerRow(
              title: show.title,
              leading: DateBlock.forDate(date),
              details: [
                show.venueName,
                '${show.measuredRsvps} RSVPs',
                recapVsAverageLabel(show.measuredRsvps, average),
              ],
            ),
            const SizedBox(height: 10),
            _TrackBar(fraction: fraction, markerFraction: averageFraction),
            if (hasNewReturning) ...[
              const SizedBox(height: 10),
              AnalyticsStackedBar(
                newFans: show.newFans!,
                returningFans: show.returningFans!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecapDetailRow extends StatelessWidget {
  const _RecapDetailRow({required this.row, required this.maxValue});

  final RecapDetailRow row;
  final num maxValue;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue <= 0
        ? 0.0
        : (row.value / maxValue).clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: '${row.label}, ${row.valueText}, ${row.meta}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LedgerRow(
              title: row.label,
              details: [row.meta],
              trailing: EpMonoText(row.valueText),
            ),
            const SizedBox(height: 10),
            _TrackBar(fraction: fraction),
          ],
        ),
      ),
    );
  }
}

class _TrackBar extends StatelessWidget {
  const _TrackBar({required this.fraction, this.markerFraction});

  final double fraction;
  final double? markerFraction;

  @override
  Widget build(BuildContext context) {
    final fillFraction = fraction.clamp(0.0, 1.0).toDouble();
    final marker = markerFraction?.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 8,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: context.epColors.panel),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fillFraction,
                heightFactor: 1,
                child: ColoredBox(color: context.epColors.ink),
              ),
            ),
          ),
          if (marker != null)
            Align(
              alignment: Alignment(-1 + 2 * marker, 0),
              child: Container(
                width: 1,
                height: 8,
                color: context.epColors.outline,
              ),
            ),
        ],
      ),
    );
  }
}
