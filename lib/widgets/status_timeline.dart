import 'package:flutter/material.dart';

import '../theme.dart';

enum TimelineStepState { done, current, pending, blocked }

class TimelineStep {
  const TimelineStep({required this.label, this.caption, required this.state});

  final String label;
  final String? caption;
  final TimelineStepState state;
}

class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.steps});

  final List<TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < steps.length; index++)
          Semantics(
            key: Key('timeline-step-$index'),
            label: '${steps[index].label}, ${steps[index].state.name}',
            excludeSemantics: true,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 22,
                    child: Column(
                      children: [
                        const SizedBox(height: 3),
                        _TimelineIndicator(state: steps[index].state),
                        if (index < steps.length - 1) ...[
                          const SizedBox(height: 4),
                          Expanded(
                            child: Container(
                              width: 1.5,
                              color: context.epColors.border,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            steps[index].label,
                            style: epText(size: 13, weight: FontWeight.w800),
                          ),
                          if (steps[index].caption case final caption?) ...[
                            const SizedBox(height: 3),
                            Text(
                              caption,
                              style: epText(
                                size: 11,
                                color: context.epColors.contentDisabled,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TimelineIndicator extends StatelessWidget {
  const _TimelineIndicator({required this.state});

  final TimelineStepState state;

  @override
  Widget build(BuildContext context) {
    final colors = context.epColors;

    return switch (state) {
      TimelineStepState.done => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: colors.success,
          shape: BoxShape.circle,
        ),
      ),
      TimelineStepState.current => Container(
        width: 16,
        height: 16,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.accent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
      TimelineStepState.pending => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.border, width: 1.5),
        ),
      ),
      TimelineStepState.blocked => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: colors.destructiveTint,
          shape: BoxShape.circle,
          border: Border.all(color: colors.destructive, width: 1.5),
        ),
      ),
    };
  }
}
