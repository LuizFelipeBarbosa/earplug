import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.errorText,
    this.suffixIcon,
    this.textInputAction,
    this.onSubmitted,
    this.inputFormatters,
    this.prefixText,
    this.prefixIcon,
    this.autocorrect,
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
  final String? errorText;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final String? prefixText;
  final Widget? prefixIcon;
  final bool? autocorrect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: FieldLabel(label, required: required)),
        const SizedBox(height: 8),
        Semantics(
          label: required ? '$label · REQUIRED' : label,
          child: TextField(
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
            style: Theme.of(context).textTheme.epInput,
            textInputAction:
                textInputAction ??
                (maxLines == 1
                    ? TextInputAction.next
                    : TextInputAction.newline),
            onSubmitted: onSubmitted,
            inputFormatters: inputFormatters,
            autocorrect:
                autocorrect ??
                (keyboardType != TextInputType.emailAddress &&
                    keyboardType != TextInputType.url),
            decoration: epInputDecoration(context, hint).copyWith(
              errorText: errorText,
              suffixIcon: suffixIcon,
              prefixText: prefixText,
              prefixIcon: prefixIcon,
            ),
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

/// Related fields share a row only when both have enough room to be readable.
class EpFieldRow extends StatelessWidget {
  const EpFieldRow({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 480 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final fieldWidth = stacked
            ? constraints.maxWidth
            : (constraints.maxWidth - EpLayout.fieldGap) / 2;
        // Wrapping the same children keeps input focus and selection intact
        // when the available width changes during editing.
        return Wrap(
          spacing: EpLayout.fieldGap,
          runSpacing: EpLayout.fieldGap,
          children: [
            SizedBox(width: fieldWidth, child: first),
            SizedBox(width: fieldWidth, child: second),
          ],
        );
      },
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
        fontWeight: FontWeight.w600,
        letterSpacing: .4,
        color: context.epColors.contentSecondary,
      ),
    );
  }
}

/// Extracts a clean, user-facing message from a thrown error.
///
/// Convex mutations that throw an uncaught server-side error surface to the
/// client as an exception whose message looks like:
///
/// ```text
///   [Request ID: …] Server Error
///   Uncaught Error: <message>
///    at handler (<file>:<line>:<col>)
/// ```
///
/// This strips that wrapper and any trailing stack-trace lines, returning
/// just `<message>`. It also strips the common local prefixes Dart adds
/// (`Bad state: `, `Exception: `, `ConvexError: `) when the wrapper isn't
/// present. Returns `null` when [error]'s text doesn't match any recognized
/// shape, so callers can substitute their own generic fallback message.
String? serverErrorMessage(Object error) {
  final text = error.toString();
  const marker = 'Uncaught Error:';
  final index = text.lastIndexOf(marker);
  if (index >= 0) {
    for (final line in text.substring(index + marker.length).split('\n')) {
      final message = line.trim();
      if (message.isNotEmpty) return message;
    }
    return null;
  }
  for (final prefix in const ['Bad state: ', 'Exception: ', 'ConvexError: ']) {
    if (text.startsWith(prefix)) return text.substring(prefix.length).trim();
  }
  return null;
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
    this.secondaryKey,
    this.onSecondary,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final Key? secondaryKey;
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = EpLayout.stackActions(context);
              final primary = FilledButton(
                onPressed: onPrimary,
                child: Text(
                  primaryLabel.toUpperCase(),
                  textAlign: TextAlign.center,
                ),
              );
              final secondary = secondaryLabel == null
                  ? null
                  : OutlinedButton(
                      key: secondaryKey,
                      onPressed: onSecondary,
                      child: Text(
                        secondaryLabel!.toUpperCase(),
                        textAlign: TextAlign.center,
                      ),
                    );
              if (stacked) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (secondary != null) ...[
                      secondary,
                      const SizedBox(height: 8),
                    ],
                    primary,
                  ],
                );
              }
              return Row(
                children: [
                  if (secondary != null) ...[
                    Expanded(child: secondary),
                    const SizedBox(width: 10),
                  ],
                  Expanded(flex: secondary == null ? 1 : 2, child: primary),
                ],
              );
            },
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

/// A form section uses whitespace and a heading to group its controls.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.count,
  });

  final String title;
  final String description;
  final Widget child;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBar.form(label: title, count: count),
        Text(description, style: Theme.of(context).textTheme.epCaption),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}
