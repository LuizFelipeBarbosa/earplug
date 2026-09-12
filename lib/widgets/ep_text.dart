import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

class EpDisplay extends StatelessWidget {
  const EpDisplay(
    this.text, {
    super.key,
    this.size = 44,
    this.color,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign = TextAlign.start,
    this.keepCase = false,
  });

  final String text;
  final double size;
  final Color? color;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final bool keepCase;

  @override
  Widget build(BuildContext context) => Text(
    keepCase ? text : text.toUpperCase(),
    semanticsLabel: text,
    style: Theme.of(context).textTheme
        .epDisplayAt(size)
        .copyWith(color: color ?? context.epColors.ink),
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}

class EpEyebrow extends StatelessWidget {
  const EpEyebrow(this.text, {super.key, this.color, this.keepCase = false})
    : _accent = false;

  const EpEyebrow.accent(this.text, {super.key, this.keepCase = false})
    : color = null,
      _accent = true;

  final String text;
  final Color? color;
  final bool keepCase;
  final bool _accent;

  @override
  Widget build(BuildContext context) => Text(
    keepCase ? text : text.toUpperCase(),
    semanticsLabel: text,
    style: Theme.of(context).textTheme.epSection.copyWith(
      color:
          color ?? (_accent ? context.epColors.accent : context.epColors.muted),
    ),
  );
}

class EpMonoText extends StatelessWidget {
  const EpMonoText(
    this.text, {
    super.key,
    this.size = 11,
    this.color,
    this.weight = FontWeight.w400,
    this.keepCase = false,
  });

  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  final bool keepCase;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = weight == FontWeight.w500
        ? textTheme.epLabel
        : textTheme.epChipLabel;
    return Text(
      keepCase ? text : text.toUpperCase(),
      semanticsLabel: text,
      style: style.copyWith(
        fontSize: size,
        color: color ?? context.epColors.ink,
      ),
    );
  }
}

enum EpPillVariant { primary, ink, outline, ghost }

enum EpPillSize { chip, regular, large }

class EpPill extends StatelessWidget {
  const EpPill({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = EpPillVariant.outline,
    this.size = EpPillSize.chip,
    this.icon,
    this.expand = false,
    this.selected = false,
    this.semanticLabel,
    this.keepCase = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final EpPillVariant variant;
  final EpPillSize size;
  final IconData? icon;
  final bool expand;
  final bool selected;
  final String? semanticLabel;
  final bool keepCase;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final enabled = onPressed != null;
    final effectiveVariant = selected && variant == EpPillVariant.outline
        ? EpPillVariant.ink
        : variant;
    final background = !enabled
        ? Colors.transparent
        : switch (effectiveVariant) {
            EpPillVariant.primary => palette.accent,
            EpPillVariant.ink => palette.ink,
            EpPillVariant.outline || EpPillVariant.ghost => Colors.transparent,
          };
    final foreground = !enabled
        ? palette.contentDisabled
        : switch (effectiveVariant) {
            EpPillVariant.primary || EpPillVariant.ink => palette.onAccent,
            EpPillVariant.outline || EpPillVariant.ghost => palette.ink,
          };
    final shape = StadiumBorder(
      side: !enabled || effectiveVariant == EpPillVariant.outline
          ? BorderSide(color: palette.outline)
          : BorderSide.none,
    );
    final (horizontal, vertical, minHeight, labelSize) = switch (size) {
      EpPillSize.chip => (16.0, 8.0, 36.0, 11.0),
      EpPillSize.regular => (24.0, 12.0, 44.0, 12.0),
      EpPillSize.large => (32.0, 16.0, 52.0, 12.0),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: SizedBox(
        width: expand ? double.infinity : null,
        child: Material(
          color: background,
          shape: shape,
          child: InkWell(
            onTap: onPressed,
            customBorder: shape,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal,
                  vertical: vertical,
                ),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: foreground),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        keepCase ? label : label.toUpperCase(),
                        semanticsLabel: label,
                        textAlign: TextAlign.center,
                        style:
                            (size == EpPillSize.chip
                                    ? Theme.of(context).textTheme.epChipLabel
                                    : Theme.of(context).textTheme.epLabel)
                                .copyWith(
                                  fontSize: labelSize,
                                  color: foreground,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EpIconPill extends StatelessWidget {
  const EpIconPill({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    return Tooltip(
      message: semanticLabel,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: semanticLabel,
        onTap: onPressed,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: Ink(
                  width: 36,
                  height: 36,
                  decoration: ShapeDecoration(
                    color: filled ? palette.accent : Colors.transparent,
                    shape: CircleBorder(
                      side: BorderSide(color: palette.outline),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: onPressed == null
                        ? palette.contentDisabled
                        : filled
                        ? palette.onAccent
                        : palette.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EpHairline extends StatelessWidget {
  const EpHairline({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    color: context.epColors.line,
    indent: indent,
    endIndent: endIndent,
  );
}

enum EpBadgeVariant { outline, secondary }

class EpBadge extends StatelessWidget {
  const EpBadge({
    super.key,
    required this.label,
    this.variant = EpBadgeVariant.outline,
  });

  final String label;
  final EpBadgeVariant variant;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(2),
      border: variant == EpBadgeVariant.outline
          ? Border.all(color: context.epColors.line)
          : null,
      color: variant == EpBadgeVariant.secondary
          ? context.epColors.panel
          : null,
    ),
    child: EpMonoText(label),
  );
}

class EpPanel extends StatelessWidget {
  const EpPanel({
    super.key,
    this.child,
    this.height,
    this.padding = EdgeInsets.zero,
    this.striped = false,
    this.color,
  });

  final Widget? child;
  final double? height;
  final EdgeInsets padding;
  final bool striped;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    color: color ?? context.epColors.panel,
    child: CustomPaint(
      painter: striped
          ? _StripePainter(context.epColors.ink.withValues(alpha: .04))
          : null,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class _StripePainter extends CustomPainter {
  const _StripePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double y = 0; y < size.height; y += 8) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripePainter oldDelegate) => color != oldDelegate.color;
}

class EpPoster extends StatelessWidget {
  const EpPoster({
    super.key,
    required this.title,
    this.eyebrow,
    this.footer,
    this.height = 220,
    this.titleSize = 40,
    this.padding = const EdgeInsets.all(18),
    this.image,
    this.style,
    this.onTap,
  });

  final String title;
  final String? eyebrow;
  final String? footer;
  final double height;
  final double titleSize;
  final EdgeInsets padding;
  final ImageProvider<Object>? image;
  final FlyerStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.epColors;
    final theme = Theme.of(context);
    final poster = SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image case final posterImage?)
            Image(image: posterImage, fit: BoxFit.cover)
          else
            EpPanel(
              striped: style == null,
              color: style?.base,
              child: style == null
                  ? null
                  : CustomPaint(painter: _StripePainter(style!.patternColor)),
            ),
          if (image != null)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    palette.background.withValues(alpha: 0),
                    palette.background.withValues(alpha: .85),
                  ],
                ),
              ),
            ),
          Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) EpEyebrow(eyebrow!),
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Theme(
                      data: theme.copyWith(
                        textTheme: theme.textTheme.copyWith(
                          displayLarge: theme.textTheme.epDisplay.copyWith(
                            height: .9,
                          ),
                        ),
                      ),
                      child: EpDisplay(
                        title,
                        size: titleSize,
                        color: style?.fg,
                      ),
                    ),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 8),
                  EpMonoText(
                    footer!,
                    color: palette.ink.withValues(alpha: .85),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return poster;
    return Semantics(
      button: true,
      child: Stack(
        children: [
          poster,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap),
            ),
          ),
        ],
      ),
    );
  }
}

class EpBottomCta extends StatelessWidget {
  const EpBottomCta({super.key, required this.child, this.hint});

  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        stops: const [.7, 1],
        colors: [
          context.epColors.background,
          context.epColors.background.withValues(alpha: 0),
        ],
      ),
    ),
    child: SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hint != null) ...[
              Center(child: EpEyebrow(hint!)),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    ),
  );
}
