import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../date_names.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_sheet.dart';
import 'ep_text.dart';
import 'sheets.dart';

/// Presents the full readiness checklist for [bandId]. Every way of leaving
/// the sheet (close button, barrier tap, drag) acknowledges the regression it
/// was showing, so the sheet never auto-opens twice for the same one.
Future<void> showReadinessSheet(BuildContext context, String bandId) async {
  final app = context.read<AppState>();
  await showEpSheet(context, (_) => ReadinessSheet(bandId: bandId));
  app.acknowledgeReadinessRegression(bandId);
}

/// The nine readiness steps split into what is left and what is done, with
/// the regression banner when a step that used to pass now fails.
class ReadinessSheet extends StatelessWidget {
  const ReadinessSheet({super.key, required this.bandId});

  final String bandId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final palette = context.epColors;
    final snapshot = app.readinessSnapshotFor(bandId);
    final regression = app.readinessRegressionFor(bandId);
    final steps = snapshot?.steps ?? const <ReadinessStep>[];
    final todo = snapshot?.todo ?? const <ReadinessStep>[];
    final finished = snapshot?.finished ?? const <ReadinessStep>[];

    void act(ReadinessStep step) {
      Navigator.of(context).pop();
      app.performReadinessAction(bandId, step.action);
    }

    return EpSheetShell(
      key: const Key('band-readiness-sheet'),
      padding: const EdgeInsets.all(20),
      maxHeightFactor: .88,
      scrollable: true,
      mainAxisSize: MainAxisSize.min,
      header: Row(
        children: [
          EpIconPill(
            key: const Key('band-readiness-close'),
            icon: Icons.close,
            semanticLabel: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          const Expanded(child: EpEyebrow('Readiness')),
          const SizedBox(width: 12),
          EpEyebrow('${snapshot?.done ?? 0} of ${ReadinessSnapshot.total}'),
        ],
      ),
      children: [
        if (regression != null) ...[
          const SizedBox(height: 16),
          _RegressionBanner(
            labels: [
              for (final step in steps)
                if (regression.stepIds.contains(step.id)) step.label,
            ],
            since: regression.since,
          ),
        ],
        const SizedBox(height: 16),
        EpReadinessBar(
          done: snapshot?.done ?? 0,
          total: ReadinessSnapshot.total,
        ),
        const SizedBox(height: 24),
        EpEyebrow('To do · ${todo.length}'),
        const SizedBox(height: 8),
        for (final step in todo) ...[
          _TodoCard(step: step, onAction: () => act(step)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        EpEyebrow('Done · ${finished.length}'),
        for (final step in finished)
          EpChecklistRow(
            key: ValueKey('readiness-done-${step.id}'),
            done: true,
            label: step.label,
          ),
        const SizedBox(height: 20),
        EpMonoText(
          'Completes → leaves the dash. A step failing → returns.',
          key: const Key('band-readiness-rules'),
          color: palette.muted,
        ),
      ],
    );
  }
}

class _RegressionBanner extends StatelessWidget {
  const _RegressionBanner({required this.labels, required this.since});

  final List<String> labels;
  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return DecoratedBox(
      key: const Key('band-readiness-regression'),
      decoration: BoxDecoration(
        color: palette.attentionTint,
        border: Border.all(color: palette.attention),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EpEyebrow(
              'Back because something changed',
              color: palette.attention,
            ),
            const SizedBox(height: 6),
            EpMonoText(
              '${_joined(labels)} came undone ${_dayPhrase(since)}.',
              color: palette.ink,
            ),
          ],
        ),
      ),
    );
  }
}

String _joined(List<String> labels) => switch (labels.length) {
  0 => 'A step',
  1 => labels.single,
  _ => '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}',
};

/// "today", "yesterday", or "on `<weekday>`" relative to the device clock.
String _dayPhrase(DateTime since) {
  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.dateOnly(since);
  final daysAgo = today.difference(day).inDays;
  return switch (daysAgo) {
    0 => 'today',
    1 => 'yesterday',
    _ => 'on ${weekdayNames[since.weekday - 1]}',
  };
}

/// One outstanding step: label, why it matters, and the action that resolves
/// it. The card and its pill both run the action so the tap target is the
/// whole card, not just the chip.
class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.step, required this.onAction});

  final ReadinessStep step;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return EpCard(
      key: ValueKey('readiness-todo-${step.id}'),
      onTap: onAction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(step.label, style: Theme.of(context).textTheme.epBody),
          const SizedBox(height: 4),
          EpMonoText(step.reason, color: palette.contentSecondary),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: EpPill(
              key: ValueKey('readiness-action-${step.id}'),
              label: step.actionLabel,
              variant: EpPillVariant.outline,
              size: EpPillSize.chip,
              onPressed: onAction,
            ),
          ),
        ],
      ),
    );
  }
}
