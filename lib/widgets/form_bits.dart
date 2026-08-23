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
        color: ready ? Ep.surfaceSelected : Ep.surfaceDisabled,
        border: Border.all(color: ready ? Ep.accent : Ep.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        ready ? 'READY' : 'DRAFT',
        style: Theme.of(context).textTheme.epCaption.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: ready ? Ep.contentPrimary : Ep.contentDisabled,
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
  final String semanticLabel;

  const Swatch({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.dashed = false,
    this.semanticLabel = 'Color swatch',
  });

  @override
  Widget build(BuildContext context) {
    final swatch = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: dashed ? Ep.background : null,
        shape: BoxShape.circle,
        border: dashed
            ? null
            : Border.all(color: selected ? Ep.accent : Ep.border, width: 2),
      ),
      child: dashed
          ? DashedBox(
              padding: EdgeInsets.zero,
              radius: 15,
              color: selected ? Ep.accent : Ep.border,
              child: child,
            )
          : child,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          containedInkWell: true,
          customBorder: const CircleBorder(),
          child: SizedBox.square(dimension: 48, child: Center(child: swatch)),
        ),
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
  filled: true,
  fillColor: Ep.background,
  isDense: true,
  constraints: const BoxConstraints(minHeight: 48),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: const BorderSide(color: Ep.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: const BorderSide(color: Ep.accent, width: 2),
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
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: WidgetStatePropertyAll(padding),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Ep.contentDisabled
              : color ?? Ep.accent,
        ),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.epLabel.copyWith(
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: letterSpacing,
          ),
        ),
      ),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
