import 'package:flutter/material.dart';

import '../theme.dart';

/// A compact progress bar for the six discovery-readiness checks.
class ReadinessSegments extends StatelessWidget {
  const ReadinessSegments({super.key, required this.steps});

  final List<bool> steps;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${steps.where((step) => step).length} of 6 discovery checks complete',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            Expanded(
              child: Container(
                key: ValueKey('discovery-segment-$index'),
                height: 6,
                decoration: BoxDecoration(
                  color: steps[index] ? Ep.brand : context.epColors.raised,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            if (index < steps.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}
