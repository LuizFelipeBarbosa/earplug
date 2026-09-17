import 'package:earplug/widgets/status_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

void main() {
  testWidgets('status timeline renders and identifies every step state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpEp(
      tester,
      const StatusTimeline(
        steps: [
          TimelineStep(label: 'Submitted', state: TimelineStepState.done),
          TimelineStep(
            label: 'In review',
            caption: 'The venue is checking the offer.',
            state: TimelineStepState.current,
          ),
          TimelineStep(label: 'Confirmed', state: TimelineStepState.pending),
          TimelineStep(label: 'Payout', state: TimelineStepState.blocked),
        ],
      ),
      center: true,
    );

    for (var index = 0; index < 4; index++) {
      expect(find.byKey(Key('timeline-step-$index')), findsOneWidget);
    }
    expect(find.bySemanticsLabel('In review, current'), findsOneWidget);
    expect(find.bySemanticsLabel('Confirmed, pending'), findsOneWidget);
    semantics.dispose();
  });
}
