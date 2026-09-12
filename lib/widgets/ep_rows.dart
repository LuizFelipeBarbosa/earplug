import 'package:flutter/material.dart';

import '../theme.dart';
import 'ep_text.dart';

class EpDateBlock extends StatelessWidget {
  const EpDateBlock({
    super.key,
    required this.date,
    this.width = 40,
    this.daySize = 30,
  });

  final DateTime date;
  final double width;
  final double daySize;

  @override
  Widget build(BuildContext context) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpDisplay('${date.day}', size: daySize),
          const SizedBox(height: 4),
          EpEyebrow(months[date.month - 1]),
        ],
      ),
    );
  }
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
    return _EpRow(
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
    required this.leading,
    required this.title,
    this.sub,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _EpRow(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        leading,
        const SizedBox(width: 12),
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
  const EpStat(this.value, this.label);

  final String value;
  final String label;
}

class EpStatGrid extends StatelessWidget {
  const EpStatGrid({
    super.key,
    required this.stats,
    this.topLine = true,
    this.bottomLine = true,
    this.valueSize = 32,
  });

  final List<EpStat> stats;
  final bool topLine;
  final bool bottomLine;
  final double valueSize;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (topLine) const EpHairline(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cells = [
              for (final stat in stats)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EpDisplay(stat.value, size: valueSize),
                    const SizedBox(height: 4),
                    EpEyebrow(stat.label),
                  ],
                ),
            ];
            final useTwoColumns =
                constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            if (useTwoColumns) {
              final cellWidth =
                  (constraints.maxWidth - 16).clamp(0.0, double.infinity) / 2;
              return SizedBox(
                width: double.infinity,
                child: Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final cell in cells)
                      SizedBox(width: cellWidth, child: cell),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final cell in cells) Expanded(child: cell)],
            );
          },
        ),
      ),
      if (bottomLine) const EpHairline(),
    ],
  );
}

class EpFactCell extends StatelessWidget {
  const EpFactCell({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.display = true,
  });

  final String label;
  final String value;
  final String? sub;
  final bool display;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      EpEyebrow(label),
      const SizedBox(height: 8),
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
        child: LayoutBuilder(
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
                  for (final cell in cells)
                    SizedBox(width: cellWidth, child: cell),
                ],
              ),
            );
          },
        ),
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
              child: EpMonoText(
                labels[index],
                size: 11,
                color: isSelected ? palette.ink : palette.muted,
              ),
            ),
          ),
        ),
      );
      tabs.add(scrollable ? tab : Flexible(child: tab));
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
    return _EpRow(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (done)
            Icon(Icons.check, size: 16, color: palette.accent)
          else
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: required ? palette.accent : palette.outline,
                ),
              ),
            ),
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
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? sub;
  final String? trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _EpRow(
    onTap: onTap,
    button: true,
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
        if (trailingText != null)
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
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.only(top: 24, bottom: 4),
  });

  final String label;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: EpEyebrow(label)),
        if (action != null) ...[
          const SizedBox(width: 12),
          Flexible(
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: context.epColors.ink,
                textStyle: Theme.of(context).textTheme.epChipLabel,
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
        return Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: focused ? palette.accent : palette.ink,
                width: focused ? 1.5 : 1,
              ),
            ),
          ),
          child: Row(
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
                    hintStyle: Theme.of(
                      context,
                    ).textTheme.epInput.copyWith(color: palette.muted),
                    isDense: true,
                    contentPadding: const EdgeInsets.only(bottom: 12),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        );
      },
    ),
  );
}

/// Shared row spacing, hit target and divider; each row owns its content layout.
class _EpRow extends StatelessWidget {
  const _EpRow({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 16),
    this.minHeight = 44,
    this.button = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double minHeight;
  final bool button;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(padding: padding, child: child),
        ),
        const EpHairline(),
      ],
    );
    if (onTap == null && !button) return content;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
