import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'ep_rows.dart';
import 'ep_text.dart';
import 'readiness_sheet.dart';

/// The dash's compact readiness card: only the steps still to do, with the
/// finished ones behind a toggle. Renders nothing while the snapshot is
/// loading (the dash owns the retry affordance) and nothing once every step
/// is done. Tapping the card opens [ReadinessSheet].
class ReadinessModule extends StatefulWidget {
  const ReadinessModule({super.key, required this.bandId});

  final String bandId;

  @override
  State<ReadinessModule> createState() => _ReadinessModuleState();
}

class _ReadinessModuleState extends State<ReadinessModule> {
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bandId = widget.bandId;
    final snapshot = app.readinessSnapshotFor(bandId);
    if (snapshot == null || snapshot.complete) return const SizedBox.shrink();

    // The state hands out each regression's auto-open exactly once, so a
    // rebuild while the sheet is up never stacks a second one.
    if (app.readinessSheetShouldAutoOpen(bandId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showReadinessSheet(context, bandId);
      });
    }

    final palette = context.epColors;
    final finished = snapshot.finished;
    return EpCard(
      key: const Key('band-readiness'),
      onTap: () => showReadinessSheet(context, bandId),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: EpEyebrow('Readiness')),
              const SizedBox(width: 12),
              EpEyebrow(
                '${snapshot.done} of ${ReadinessSnapshot.total}',
                key: const Key('band-readiness-count'),
              ),
            ],
          ),
          if (app.readinessRegressionFor(bandId) != null) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label: 'Back because something changed',
                tone: EpStatusPillTone.attention,
              ),
            ),
          ],
          const SizedBox(height: 12),
          EpReadinessBar(done: snapshot.done, total: ReadinessSnapshot.total),
          const SizedBox(height: 4),
          for (final step in snapshot.todo)
            EpChecklistRow(
              key: ValueKey(step.id),
              done: false,
              label: step.label,
              actionLabel: step.actionLabel,
              onAction: () => app.performReadinessAction(bandId, step.action),
            ),
          if (_showCompleted)
            for (final step in finished)
              EpChecklistRow(
                key: ValueKey(step.id),
                done: true,
                label: step.label,
              ),
          if (finished.isNotEmpty)
            Center(
              child: TextButton(
                key: const Key('band-readiness-toggle'),
                onPressed: () =>
                    setState(() => _showCompleted = !_showCompleted),
                child: EpMonoText(
                  _showCompleted
                      ? 'Hide completed'
                      : 'View ${finished.length} completed',
                  color: palette.ink,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
