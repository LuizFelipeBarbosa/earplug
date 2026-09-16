import 'package:flutter/material.dart';

import '../application_tracker.dart';
import '../theme.dart';
import 'ep_text.dart';

class ApplicationTrackerBar extends StatelessWidget {
  const ApplicationTrackerBar({super.key, required this.tracker});

  final ApplicationTracker tracker;

  String get _decisionLabel => switch (tracker.outcome) {
    ApplicationOutcome.pending => 'DECISION',
    ApplicationOutcome.offered => 'OFFER',
    ApplicationOutcome.booked => 'BOOKED',
    ApplicationOutcome.declined => 'DECLINED',
    ApplicationOutcome.withdrawn => 'WITHDRAWN',
    ApplicationOutcome.expired => 'EXPIRED',
  };

  String get _semanticLabel => [
    for (final step in ApplicationTrackerStep.values)
      if (step != ApplicationTrackerStep.decision)
        '${step == ApplicationTrackerStep.applied ? 'Applied' : step.name}'
            '${tracker.reached.contains(step) ? '' : ' pending'}',
    switch (tracker.outcome) {
      ApplicationOutcome.pending => 'decision pending',
      ApplicationOutcome.offered => 'offer received',
      _ => tracker.outcome.name,
    },
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final colors = context.epColors;
    return Semantics(
      label: _semanticLabel,
      excludeSemantics: true,
      child: Row(
        children: [
          for (final step in ApplicationTrackerStep.values)
            Expanded(child: _segment(colors, step)),
        ],
      ),
    );
  }

  Widget _segment(EpPalette colors, ApplicationTrackerStep step) {
    final reached = tracker.reached.contains(step);
    var color = reached ? colors.accent : colors.contentDisabled;
    if (reached && step == ApplicationTrackerStep.decision) {
      color = switch (tracker.outcome) {
        ApplicationOutcome.booked => colors.success,
        ApplicationOutcome.declined => colors.destructive,
        ApplicationOutcome.withdrawn ||
        ApplicationOutcome.expired => colors.contentSecondary,
        _ => colors.accent,
      };
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: SizedBox(
                  height: 2,
                  child: ColoredBox(color: reached ? color : colors.border),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: EpMonoText(
              step == ApplicationTrackerStep.decision
                  ? _decisionLabel
                  : step.name,
              size: 9,
              color: color,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
