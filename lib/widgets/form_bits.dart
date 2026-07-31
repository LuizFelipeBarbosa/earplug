import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// READY / DRAFT badge in the header of a create flow.
class ReadyPill extends StatelessWidget {
  final bool ready;

  const ReadyPill({super.key, required this.ready});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ready ? Ep.blue.withValues(alpha: .2) : Ep.card,
        border: Border.all(color: ready ? Ep.blue : Ep.whiteA(.14)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        ready ? 'READY' : 'DRAFT',
        style: epText(
          size: 9.5,
          weight: FontWeight.w900,
          letterSpacing: 1.2,
          color: ready ? Ep.linkSoft : Ep.inkA(.45),
        ),
      ),
    );
  }
}

/// A round colour chip in a picker row. The `dashed` variant is the
/// "bring your own" slot, drawn as a dashed outline instead of a fill.
class Swatch extends StatelessWidget {
  final bool selected;
  final bool dashed;
  final VoidCallback onTap;
  final Widget child;

  const Swatch({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: dashed ? Ep.bg : null,
          shape: BoxShape.circle,
          border: dashed
              ? null
              : Border.all(
                  color: selected ? Ep.link : Ep.whiteA(.18),
                  width: 2,
                ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Ep.link.withValues(alpha: .25),
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: dashed
            ? DashedBox(
                padding: EdgeInsets.zero,
                radius: 15,
                color: selected ? Ep.link : Ep.whiteA(.35),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// The full-width button that dismisses a create-flow sheet.
class DoneButton extends StatelessWidget {
  const DoneButton({super.key});

  @override
  Widget build(BuildContext context) {
    return EpButton(
      'DONE',
      fontSize: 12.5,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: () => Navigator.pop(context),
    );
  }
}

/// Text-field styling for inputs that sit inside a create-flow sheet.
InputDecoration sheetInput(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: epText(size: 12.5, color: Ep.inkA(.35)),
  filled: true,
  fillColor: Ep.bg,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: Ep.whiteA(.16)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: Ep.whiteA(.3)),
  ),
);

/// A bare tappable label — no box, no fill. Defaults to the roomy tracked-out
/// form-footer look; pass the metrics for the tight inline variant.
class TextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  final double letterSpacing;
  final EdgeInsets padding;

  const TextAction(
    this.label, {
    super.key,
    required this.onTap,
    this.color,
    this.size = 11.5,
    this.letterSpacing = 1.4,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: epText(
            size: size,
            weight: FontWeight.w900,
            letterSpacing: letterSpacing,
            color: color ?? Ep.inkA(.4),
          ),
        ),
      ),
    );
  }
}
