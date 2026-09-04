import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Scrolls [controller] to its end after the next frame, so feedback that
/// just appeared below a form comes into view. No-op once [state] is gone.
void revealFormFeedback(State state, ScrollController controller) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!state.mounted || !controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  });
}

/// READY / DRAFT badge in the header of a create flow.
class ReadyPill extends StatelessWidget {
  final bool ready;

  const ReadyPill({super.key, required this.ready});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: ready
            ? context.epColors.surfaceSelected
            : context.epColors.surfaceDisabled,
        border: Border.all(
          color: ready ? context.epColors.accent : context.epColors.border,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        ready ? 'READY' : 'DRAFT',
        style: Theme.of(context).textTheme.epCaption.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: ready
              ? context.epColors.contentPrimary
              : context.epColors.contentDisabled,
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
        color: dashed ? context.epColors.background : null,
        shape: BoxShape.circle,
        border: dashed
            ? null
            : Border.all(
                color: selected
                    ? context.epColors.accent
                    : context.epColors.border,
                width: 2,
              ),
      ),
      child: dashed
          ? DashedBox(
              padding: EdgeInsets.zero,
              radius: 15,
              color: selected
                  ? context.epColors.accent
                  : context.epColors.border,
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
/// [epInputDecoration] on the page background, for fields inside sheets.
InputDecoration sheetInput(BuildContext context, String hint) =>
    epInputDecoration(
      context,
      hint,
      fillColor: context.epColors.background,
      horizontalPadding: 12,
    );

class EpLabeledField extends StatelessWidget {
  const EpLabeledField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.fieldKey,
    this.required = false,
    this.enabled = true,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onEditingComplete,
    this.focusNode,
    this.caption,
    this.autofillHints,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final Key? fieldKey;
  final bool required;
  final bool enabled;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final FocusNode? focusNode;
  final String? caption;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: fieldKey,
          controller: controller,
          enabled: enabled,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          onEditingComplete: onEditingComplete,
          focusNode: focusNode,
          autofillHints: autofillHints,
          decoration: labeledInputDecoration(
            context,
            required ? '$label · REQUIRED' : label,
            hint,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(caption!, style: Theme.of(context).textTheme.epCaption),
        ],
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Text(
      required ? '$text · REQUIRED' : text,
      style: Theme.of(context).textTheme.epLabel.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: .8,
        color: context.epColors.contentSecondary,
      ),
    );
  }
}

class InlineFormFeedback extends StatelessWidget {
  const InlineFormFeedback({
    super.key,
    this.error,
    this.success,
    this.errorKey,
    this.successKey,
  });

  final String? error;
  final String? success;
  final Key? errorKey;
  final Key? successKey;

  @override
  Widget build(BuildContext context) {
    if (error == null && success == null) return const SizedBox.shrink();

    final showingError = error != null;
    return Semantics(
      liveRegion: true,
      child: Text(
        showingError ? error! : success!,
        key: showingError ? errorKey : successKey,
        style: Theme.of(context).textTheme.epBody.copyWith(
          color: showingError
              ? context.epColors.warning
              : context.epColors.success,
        ),
      ),
    );
  }
}

/// Dashed placeholder for an empty list: a centred [message] and, when
/// [actionLabel] is given, a [TextAction] beneath it.
class EmptyNote extends StatelessWidget {
  const EmptyNote({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.style,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  /// Defaults to body text in the secondary colour.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return DashedBox(
      padding: padding,
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style:
                style ??
                Theme.of(context).textTheme.epBody.copyWith(
                  color: context.epColors.contentSecondary,
                ),
          ),
          if (actionLabel case final actionLabel?)
            TextAction(actionLabel, onTap: onAction),
        ],
      ),
    );
  }
}

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
        minimumSize: WidgetStatePropertyAll(Size(48, 48)),
        padding: WidgetStatePropertyAll(padding),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? context.epColors.contentDisabled
              : color ?? context.epColors.accent,
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

/// A compact setting control with an explicit plain-language explanation.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.caption,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final callback = enabled ? () => onChanged!(!value) : null;
    return Semantics(
      container: true,
      button: true,
      toggled: value,
      enabled: enabled,
      onTap: callback,
      label: caption == null ? label : '$label. $caption',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: context.epColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: context.epColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: callback,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: Theme.of(context).textTheme.epBody.copyWith(
                            color: enabled
                                ? context.epColors.ink
                                : context.epColors.contentDisabled,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _CompactSwitch(value: value, enabled: enabled),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (caption != null && caption!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(caption!, style: Theme.of(context).textTheme.epCaption),
          ],
        ],
      ),
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, required this.enabled});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 30,
      height: 18,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: !enabled
            ? context.epColors.surfaceDisabled
            : value
            ? Ep.brand
            : context.epColors.raised,
        border: Border.all(
          color: value && enabled ? Ep.brand : context.epColors.border,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: !enabled
                ? context.epColors.mute
                : value
                ? Colors.white
                : context.epColors.mute,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Dashed presentation for an unfinished draft with one resume action.
class GhostDraftRow extends StatelessWidget {
  const GhostDraftRow({
    super.key,
    required this.title,
    required this.missing,
    required this.onResume,
    this.actionLabel = 'RESUME →',
  });

  final String title;
  final String missing;
  final VoidCallback? onResume;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final description = 'Draft — $title · $missing';
    return Semantics(
      button: true,
      enabled: onResume != null,
      label: '$description. $actionLabel',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onResume,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: DashedBox(
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 28),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.epMeta.copyWith(
                        color: context.epColors.contentSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    actionLabel,
                    style: Theme.of(context).textTheme.epChipLabel.copyWith(
                      color: context.epColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-pinned primary/secondary actions for create and edit flows.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.epColors.tabBarBackground,
          border: Border(top: BorderSide(color: context.epColors.border)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (secondaryLabel != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!.toUpperCase()),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: secondaryLabel == null ? 1 : 2,
                child: FilledButton(
                  onPressed: onPrimary,
                  child: Text(primaryLabel.toUpperCase()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Destructive action that stays visible and explains its consequence.
class DangerZone extends StatelessWidget {
  const DangerZone({
    super.key,
    required this.label,
    required this.consequence,
    required this.onPressed,
  });

  final String label;
  final String consequence;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: context.epColors.destructive,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: Theme.of(context).textTheme.epChipLabel,
            ),
            child: Text(label.toUpperCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            consequence,
            style: Theme.of(context).textTheme.epCaption,
          ),
        ),
      ],
    );
  }
}

/// A titled block of a create/edit form: a [SectionBar] heading, a caption,
/// then [child] — inside a raised card when [boxed] is true.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.count,
    this.boxed = false,
    this.spacing = 12,
  });

  final String title;
  final String description;
  final Widget child;
  final int? count;
  final bool boxed;

  /// Gap between the caption and the body.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar(label: title, count: count),
        Text(description, style: Theme.of(context).textTheme.epCaption),
        SizedBox(height: spacing),
        if (boxed)
          EpCard(
            variant: EpCardVariant.raised,
            padding: const EdgeInsets.all(15),
            child: child,
          )
        else
          child,
      ],
    );
  }
}
