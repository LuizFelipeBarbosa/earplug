import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../date_names.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ep_sheet.dart';
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
  final prefix = 'LAST ${recap.window.showsAnalyzed} SHOWS';
  if (first == null || last == null) return prefix;
  final firstDate = DateTime.fromMillisecondsSinceEpoch(first);
  final lastDate = DateTime.fromMillisecondsSinceEpoch(last);
  return '$prefix · ${monthNamesUpper[firstDate.month - 1]} – '
      '${monthNamesUpper[lastDate.month - 1]}';
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
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        maxHeightFactor: .88,
        scrollable: true,
        mainAxisSize: MainAxisSize.min,
        header: Text(
          'ALL ${recap.shows.length} SHOWS',
          style: Theme.of(ctx).textTheme.epSectionHeading,
        ),
        children: [
          const SizedBox(height: 6),
          Text(
            recapWindowLabel(recap),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(ctx).textTheme.epSection.copyWith(
              color: ctx.epColors.contentSecondary,
            ),
          ),
          Text(
            'AVG ${recapFormatNumber(recap.totals.avgPerShow)} PER SHOW',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(ctx).textTheme.epSection.copyWith(
              color: ctx.epColors.contentSecondary,
            ),
          ),
          if (recap.window.truncated) ...[
            const SizedBox(height: 5),
            Text(
              'Only the ${recap.window.showsAnalyzed} most recent shows are '
              'analyzed.',
              style: Theme.of(ctx).textTheme.epCaption.copyWith(
                color: ctx.epColors.contentDisabled,
              ),
            ),
          ],
          const SizedBox(height: 4),
          for (var index = 0; index < shows.length; index++) ...[
            if (index > 0) _RowDivider(color: ctx.epColors.border),
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
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        maxHeightFactor: .88,
        scrollable: true,
        mainAxisSize: MainAxisSize.min,
        header: Text(title, style: Theme.of(ctx).textTheme.epSectionHeading),
        children: [
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(ctx).textTheme.epSection.copyWith(
              color: ctx.epColors.contentSecondary,
            ),
          ),
          const SizedBox(height: 4),
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) _RowDivider(color: ctx.epColors.border),
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
              ChartLegend(color: Ep.brand, label: 'NEW $newFans'),
              ChartLegend(
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

class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.color, required this.label});

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
            Row(
              children: [
                DateBlock.forDate(date),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        show.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epLabel,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        show.venueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epCaption.copyWith(
                          color: context.epColors.contentSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${show.measuredRsvps}',
                      style: Theme.of(context).textTheme.epSectionHeading
                          .copyWith(color: context.epColors.accent),
                    ),
                    Text(
                      recapVsAverageLabel(show.measuredRsvps, average),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.epCaption.copyWith(
                        color: context.epColors.contentSecondary,
                      ),
                    ),
                  ],
                ),
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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.epLabel,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row.meta,
                        style: Theme.of(context).textTheme.epCaption.copyWith(
                          color: context.epColors.contentSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  row.valueText,
                  style: Theme.of(context).textTheme.epSectionHeading.copyWith(
                    color: context.epColors.accent,
                  ),
                ),
              ],
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
              decoration: BoxDecoration(
                color: context.epColors.surfaceDisabled,
                border: Border.all(color: context.epColors.border),
                borderRadius: BorderRadius.circular(99),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fillFraction,
                heightFactor: 1,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Ep.brand),
                ),
              ),
            ),
          ),
          if (marker != null)
            Align(
              alignment: Alignment(-1 + 2 * marker, 0),
              child: Container(
                width: 1,
                height: 8,
                color: context.epColors.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}
