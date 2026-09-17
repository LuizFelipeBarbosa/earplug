import 'package:flutter/material.dart';

import '../date_names.dart';
import '../theme.dart';
import 'ep_text.dart';

class EpDateBlock extends StatelessWidget {
  const EpDateBlock({
    super.key,
    required this.date,
    this.width = 44,
    this.daySize = 30,
  });

  final DateTime date;
  final double width;
  final double daySize;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpDisplay(
          '${date.day}',
          size: daySize,
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
        const SizedBox(height: 4),
        EpEyebrow(monthNames[date.month - 1]),
      ],
    ),
  );
}

class EpGigRow extends StatelessWidget {
  const EpGigRow({
    super.key,
    required this.date,
    required this.title,
    this.meta,
    this.sub,
    this.trailing,
    this.onTap,
    this.titleSize = 24,
  });

  final DateTime date;
  final String title;
  final String? meta;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final end =
        trailing ??
        (onTap == null
            ? null
            : Icon(Icons.chevron_right, size: 16, color: palette.muted));
    return EpRow(
      onTap: onTap,
      minHeight: 48,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EpDateBlock(date: date),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EpDisplay(title, size: titleSize, maxLines: 3),
                  if (meta != null) ...[
                    const SizedBox(height: 8),
                    EpMonoText(meta!, color: palette.muted),
                  ],
                  if (sub != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      sub!,
                      style: Theme.of(
                        context,
                      ).textTheme.epBody.copyWith(color: palette.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (end != null) ...[
              const SizedBox(width: 12),
              Align(alignment: Alignment.centerRight, child: end),
            ],
          ],
        ),
      ),
    );
  }
}

class EpEntityRow extends StatelessWidget {
  const EpEntityRow({
    super.key,
    this.leading,
    required this.title,
    this.sub,
    this.subMaxLinesOne = false,
    this.trailing,
    this.onTap,
  });

  final Widget? leading;
  final String title;
  final String? sub;
  final bool subMaxLinesOne;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => EpRow(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EpDisplay(title, size: 20),
              if (sub != null) ...[
                const SizedBox(height: 4),
                Text(
                  sub!,
                  maxLines: subMaxLinesOne ? 1 : null,
                  overflow: subMaxLinesOne ? TextOverflow.ellipsis : null,
                  style: Theme.of(
                    context,
                  ).textTheme.epBody.copyWith(color: context.epColors.muted),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    ),
  );
}

class EpAvatarTile extends StatelessWidget {
  const EpAvatarTile({
    super.key,
    required this.initials,
    this.size = 40,
    this.accent = false,
    this.image,
  });

  final String initials;
  final double size;
  final bool accent;
  final ImageProvider<Object>? image;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: accent ? context.epColors.accent : context.epColors.panel,
      image: image == null
          ? null
          : DecorationImage(image: image!, fit: BoxFit.cover),
    ),
    child: image != null
        ? null
        : Center(
            child: EpDisplay(
              initials,
              size: size * .45,
              color: accent ? context.epColors.onAccent : context.epColors.ink,
            ),
          ),
  );
}

class EpStat {
  const EpStat(this.value, this.label, {this.onTap, this.key});

  final String value;
  final String label;
  final VoidCallback? onTap;
  final Key? key;
}

class _EpStatCell extends StatelessWidget {
  const _EpStatCell({
    required this.stat,
    required this.valueSize,
    required this.fitLabel,
  });

  final EpStat stat;
  final double valueSize;
  final bool fitLabel;

  @override
  Widget build(BuildContext context) {
    final label = EpEyebrow(stat.label);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpDisplay(stat.value, size: valueSize),
        const SizedBox(height: 4),
        if (fitLabel)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: label,
          )
        else
          label,
      ],
    );
    final child = stat.onTap == null
        ? column
        : Semantics(
            button: true,
            label: '${stat.label}, ${stat.value}',
            child: InkWell(onTap: stat.onTap, child: column),
          );
    return KeyedSubtree(key: stat.key, child: child);
  }
}

class EpStatGrid extends StatelessWidget {
  const EpStatGrid({
    super.key,
    required this.stats,
    this.topLine = true,
    this.bottomLine = true,
    this.valueSize = 32,
    this.dividers = false,
    this.wrap = true,
    this.fitLabels = false,
  });

  final List<EpStat> stats;
  final bool topLine;
  final bool bottomLine;
  final double valueSize;

  /// A hairline between adjacent cells, stretched to the tallest cell.
  final bool dividers;

  /// Fall back to two columns when the grid is narrow or text is enlarged.
  final bool wrap;

  /// Scale a label down to its cell instead of wrapping it.
  final bool fitLabels;

  @override
  Widget build(BuildContext context) {
    final cells = [
      for (final stat in stats)
        _EpStatCell(stat: stat, valueSize: valueSize, fitLabel: fitLabels),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topLine) const EpHairline(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: wrap
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final useTwoColumns =
                        constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3;
                    if (useTwoColumns) {
                      return _EpCellWrap(cells: cells, columns: 2);
                    }
                    return _row(context, cells);
                  },
                )
              : _row(context, cells),
        ),
        if (bottomLine) const EpHairline(),
      ],
    );
  }

  Widget _row(BuildContext context, List<Widget> cells) {
    if (!dividers) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final cell in cells) Expanded(child: cell)],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < cells.length; index++) ...[
            if (index > 0)
              SizedBox(
                width: 1,
                child: ColoredBox(color: context.epColors.border),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: index == 0 ? 0 : 16, right: 8),
                child: cells[index],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Equal-width cells, 16px apart, flowing onto new rows every [columns].
class _EpCellWrap extends StatelessWidget {
  const _EpCellWrap({required this.cells, required this.columns});

  final List<Widget> cells;
  final int columns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cellWidth =
          (constraints.maxWidth - 16 * (columns - 1)).clamp(
            0.0,
            double.infinity,
          ) /
          columns;
      return SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final cell in cells) SizedBox(width: cellWidth, child: cell),
          ],
        ),
      );
    },
  );
}

class EpFactCell extends StatelessWidget {
  const EpFactCell({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.display = true,
    this.note,
  });

  final String label;
  final String value;
  final String? sub;
  final bool display;

  /// A muted mono line shown in place of the value and sub.
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      EpEyebrow(label),
      const SizedBox(height: 8),
      if (note != null)
        EpMonoText(note!, color: context.epColors.muted)
      else ...[
        if (display)
          EpDisplay(value, size: 24)
        else
          Text(value, style: Theme.of(context).textTheme.epBody),
        if (sub != null) ...[
          const SizedBox(height: 4),
          Text(
            sub!,
            style: Theme.of(
              context,
            ).textTheme.epBody.copyWith(color: context.epColors.muted),
          ),
        ],
      ],
    ],
  );
}

class EpFactGrid extends StatelessWidget {
  const EpFactGrid({
    super.key,
    required this.cells,
    this.columns = 2,
    this.bottomLine = true,
  }) : assert(columns > 0);

  final List<Widget> cells;
  final int columns;
  final bool bottomLine;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: _EpCellWrap(cells: cells, columns: columns),
      ),
      if (bottomLine) const EpHairline(),
    ],
  );
}

class EpSegmentTabs extends StatelessWidget {
  const EpSegmentTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.scrollable = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final tabs = <Widget>[];
    for (var index = 0; index < labels.length; index++) {
      if (index > 0) tabs.add(const SizedBox(width: 24));
      final isSelected = index == selected;
      // Labels never wrap: a scrollable strip gives them unbounded width, a
      // fixed strip scales a label down when its segment is narrower than it.
      final label = EpMonoText(
        labels[index],
        size: 11,
        color: isSelected ? palette.ink : palette.muted,
        maxLines: 1,
      );
      final tab = Semantics(
        selected: isSelected,
        button: true,
        inMutuallyExclusiveGroup: true,
        child: InkWell(
          onTap: () => onSelect(index),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected ? palette.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: scrollable
                  ? label
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: label,
                    ),
            ),
          ),
        ),
      );
      // Segments share the width in proportion to their label length so a
      // long label borrows the slack of short ones before it has to shrink.
      tabs.add(
        scrollable ? tab : Flexible(flex: labels[index].length + 1, child: tab),
      );
    }
    final row = Row(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: tabs,
    );
    return Stack(
      children: [
        const Positioned(left: 0, right: 0, bottom: 0, child: EpHairline()),
        if (scrollable)
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: row)
        else
          row,
      ],
    );
  }
}

class EpSegment {
  const EpSegment({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    this.key,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final Key? key;
}

/// A pill-shaped, mutually exclusive icon and label switch.
class EpSegmentedControl extends StatelessWidget {
  const EpSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelect,
  }) : assert(segments.length >= 2);

  final List<EpSegment> segments;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: palette.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < segments.length; index++)
              Semantics(
                key: segments[index].key,
                button: true,
                selected: index == selected,
                inMutuallyExclusiveGroup: true,
                label: segments[index].semanticLabel,
                excludeSemantics: true,
                child: Material(
                  color: index == selected ? palette.ink : Colors.transparent,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onSelect(index),
                    child: SizedBox(
                      height: 32,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              segments[index].icon,
                              size: 14,
                              color: index == selected
                                  ? palette.onAccent
                                  : palette.ink,
                            ),
                            const SizedBox(width: 6),
                            EpMonoText(
                              segments[index].label,
                              color: index == selected
                                  ? palette.onAccent
                                  : palette.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class EpReadinessBar extends StatelessWidget {
  const EpReadinessBar({super.key, required this.done, required this.total})
    : assert(total >= 0),
      assert(done >= 0 && done <= total);

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$done of $total complete',
    excludeSemantics: true,
    child: Row(
      children: [
        for (var index = 0; index < total; index++) ...[
          if (index > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              key: ValueKey('readiness-segment-$index'),
              height: 3,
              color: index < done
                  ? context.epColors.accent
                  : context.epColors.panel,
            ),
          ),
        ],
      ],
    ),
  );
}

class EpChecklistRow extends StatelessWidget {
  const EpChecklistRow({
    super.key,
    required this.done,
    required this.label,
    this.actionLabel,
    this.onAction,
    this.required = false,
  });

  final bool done;
  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return EpRow(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (done)
            Icon(Icons.check, size: 16, color: palette.accent)
          else
            EpDot(border: required ? palette.accent : palette.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.epBody),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  textStyle: Theme.of(context).textTheme.epChipLabel,
                ),
                child: EpMonoText(actionLabel!, color: palette.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class EpMenuRow extends StatelessWidget {
  const EpMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.sub,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
  });

  final IconData icon;
  final String label;
  final String? sub;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => EpRow(
    onTap: onTap,
    button: true,
    padding: padding,
    child: Row(
      children: [
        Icon(icon, size: 16, color: context.epColors.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EpDisplay(label, size: 20),
              if (sub != null) ...[
                const SizedBox(height: 4),
                Text(
                  sub!,
                  style: Theme.of(
                    context,
                  ).textTheme.epBody.copyWith(color: context.epColors.muted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (trailing != null)
          trailing!
        else if (trailingText != null)
          Flexible(
            child: EpMonoText(trailingText!, color: context.epColors.muted),
          )
        else
          Icon(Icons.chevron_right, size: 16, color: context.epColors.muted),
      ],
    ),
  );
}

class EpSectionHeader extends StatelessWidget {
  const EpSectionHeader({
    super.key,
    required this.label,
    this.count,
    this.trailing,
    this.action,
    this.actionKey,
    this.onAction,
    this.padding = const EdgeInsets.only(top: 24, bottom: 4),
  });

  /// A header spaced for the gap between form sections.
  const EpSectionHeader.form({
    super.key,
    required this.label,
    this.count,
    this.trailing,
    this.action,
    this.actionKey,
    this.onAction,
  }) : padding = const EdgeInsets.only(top: EpLayout.formSectionGap, bottom: 4);

  final String label;

  /// Appended to the label as "LABEL · 3".
  final int? count;

  /// Sits right of the eyebrow, before any [action].
  final Widget? trailing;
  final String? action;
  final Key? actionKey;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: EpEyebrow(count == null ? label : '$label · $count')),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Flexible(child: trailing!),
        ],
        if (action != null) ...[
          const SizedBox(width: 12),
          Flexible(
            child: TextButton(
              key: actionKey,
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: context.epColors.ink,
                textStyle: Theme.of(context).textTheme.epChipLabel,
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: Alignment.centerRight,
              ),
              child: EpMonoText(action!),
            ),
          ),
        ],
      ],
    ),
  );
}

class EpUnderlineField extends StatelessWidget {
  const EpUnderlineField({
    super.key,
    this.controller,
    this.hint,
    this.icon,
    this.trailing,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.autofocus = false,
    this.focusNode,
    this.fieldKey,
    this.textInputAction,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final Widget? trailing;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final bool autofocus;
  final FocusNode? focusNode;
  final Key? fieldKey;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    child: Builder(
      builder: (context) {
        final palette = context.epColors;
        final focused = Focus.of(context).hasFocus;
        // The row centres everything on one axis so a tall trailing pill,
        // the icon and the text share a baseline band; the gap to the
        // underline lives on the container so the trailing never sits on it.
        return Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: focused ? palette.accent : palette.ink,
                width: focused ? 1.5 : 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: palette.muted),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  keyboardType: keyboardType,
                  autofocus: autofocus,
                  textInputAction: textInputAction,
                  autofillHints: autofillHints,
                  style: Theme.of(context).textTheme.epInput,
                  decoration: InputDecoration(
                    hintText: hint,
                    // Drop the theme's minimum height: without a visible
                    // border the decorator top-aligns its text in the spare
                    // space, floating it above the icon and trailing control.
                    // The row centres the natural-height field instead.
                    constraints: const BoxConstraints(),
                    hintStyle: Theme.of(
                      context,
                    ).textTheme.epInput.copyWith(color: palette.muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        );
      },
    ),
  );
}

/// Shared row spacing, hit target and divider; each row owns its content layout.
class EpRow extends StatelessWidget {
  const EpRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
    this.minHeight = 44,
    this.button = false,
    this.semanticLabel,
    this.showHairline = true,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double minHeight;

  /// Announce as a button even without [onTap].
  final bool button;

  /// Label for the button node; only emitted when the row is a button.
  final String? semanticLabel;
  final bool showHairline;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(padding: padding, child: child),
        ),
        if (showHairline) const EpHairline(),
      ],
    );
    if (onTap == null && !button) return content;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
