import 'package:flutter/material.dart';

import '../theme.dart';

/// How far a scroll view has travelled into its header fade, 0 before it
/// scrolls and 1 once [fade] pixels have gone by. Safe to call before the
/// controller is attached.
double scrollFadeProgress(ScrollController controller, {double fade = 80}) =>
    ((controller.hasClients ? controller.offset : 0.0) / fade).clamp(0.0, 1.0);

/// The mini header that fades in over a scrolling hero: a background and
/// bottom hairline that both lerp from transparent to solid with [progress],
/// while [title] fades in between [leading] and the [trailing] controls.
///
/// [barKey] lands on the outer [Container] so tests can read its decoration.
/// With [hairlineInForeground] the hairline paints as a foreground decoration,
/// leaving the full [height] to the centred row; otherwise it is part of the
/// background border and subtracts from the row's height.
class EpScrollHeaderBar extends StatelessWidget {
  const EpScrollHeaderBar({
    super.key,
    required this.barKey,
    required this.topInset,
    required this.progress,
    this.height = 56,
    this.hairlineInForeground = true,
    required this.leading,
    required this.title,
    this.trailing = const [],
  });

  final Key barKey;
  final double topInset;
  final double progress;
  final double height;
  final bool hairlineInForeground;
  final Widget leading;
  final Widget title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.epColors;
    final hairline = Border(
      bottom: BorderSide(
        color: Color.lerp(
          colors.line.withValues(alpha: 0),
          colors.line,
          progress,
        )!,
      ),
    );
    return Container(
      key: barKey,
      height: height + topInset,
      padding: EdgeInsets.only(top: topInset),
      decoration: BoxDecoration(
        color: Color.lerp(
          colors.background.withValues(alpha: 0),
          colors.background,
          progress,
        ),
        border: hairlineInForeground ? null : hairline,
      ),
      foregroundDecoration: hairlineInForeground
          ? BoxDecoration(border: hairline)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EpLayout.gutter),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(opacity: progress, child: title),
            ),
            ...trailing,
          ],
        ),
      ),
    );
  }
}
