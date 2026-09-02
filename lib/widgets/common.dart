import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Top padding for screen headers: status bar / notch plus breathing room.
double headerTopPad(BuildContext context) =>
    math.max(MediaQuery.paddingOf(context).top, 24) + 10;

/// Bottom inset used by scrollables so content clears the floating tab bar.
const double tabBarClearance = 96;

class EpNetworkImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;

  const EpNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final bool blue;

  const SectionLabel(this.text, {super.key, this.blue = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.epLabel.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: blue
            ? context.epColors.accent
            : context.epColors.contentSecondary,
      ),
    );
  }
}

/// Calendar/list section heading used by both fan and band surfaces.
class SectionBar extends StatelessWidget {
  const SectionBar({
    super.key,
    required this.label,
    this.count,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 20, bottom: 10),
  });

  final String label;
  final int? count;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final text = count == null
        ? label.toUpperCase()
        : '${label.toUpperCase()} · $count';
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: context.epColors.volt,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.epSection,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A date-first visual anchor for event and history rows.
class DateBlock extends StatelessWidget {
  const DateBlock({
    super.key,
    required this.day,
    required this.month,
    this.semanticLabel,
    this.size = 40,
  });

  final String day;
  final String month;
  final String? semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? '${month.trim()} ${day.trim()}',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.epColors.raised,
              border: Border.all(color: context.epColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: MediaQuery.withNoTextScaling(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      day.trim(),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.epDisplay.copyWith(
                        fontSize: size * .43,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      month.trim().toUpperCase(),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.epChipLabel.copyWith(
                        color: context.epColors.volt,
                        fontSize: math.max(11, size * .175),
                        letterSpacing: 1.1,
                        height: 1,
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

/// Rounded filter/selection chip (the spec's chipStyle).
class EpChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool ghost;
  final bool neutralSelected;
  final VoidCallback? onRemoved;
  final String? semanticLabel;

  const EpChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.ghost = false,
    this.neutralSelected = false,
    this.onRemoved,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || onRemoved != null;
    final textStyle = Theme.of(context).textTheme.epChipLabel.copyWith(
      color: !enabled
          ? context.epColors.contentDisabled
          : active
          ? neutralSelected
                ? context.epColors.contentPrimary
                : context.epColors.dark
          : ghost
          ? context.epColors.mute
          : context.epColors.contentSecondary,
    );
    if (ghost) {
      return Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel ?? label,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Center(
                child: DashedBox(
                  expand: false,
                  radius: 99,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(label.toUpperCase(), style: textStyle),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (onRemoved != null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: InputChip(
          label: Text(label.toUpperCase(), style: textStyle),
          selected: active,
          onPressed: onTap,
          onDeleted: onRemoved,
          deleteIcon: Icon(Icons.close, size: 16),
          deleteIconColor: active && !neutralSelected
              ? context.epColors.dark
              : context.epColors.mute,
          showCheckmark: false,
          backgroundColor: Colors.transparent,
          selectedColor: neutralSelected
              ? context.epColors.surfaceDisabled
              : context.epColors.volt,
          disabledColor: Colors.transparent,
          side: BorderSide(
            color: active && neutralSelected
                ? context.epColors.contentSecondary
                : active
                ? context.epColors.volt
                : context.epColors.border,
          ),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: FilterChip(
        label: Text(label.toUpperCase(), style: textStyle),
        selected: active,
        onSelected: onTap == null ? null : (_) => onTap!(),
        onDeleted: onRemoved,
        deleteIcon: Icon(Icons.close, size: 16),
        deleteIconColor: active && !neutralSelected
            ? context.epColors.dark
            : context.epColors.mute,
        showCheckmark: false,
        backgroundColor: Colors.transparent,
        selectedColor: neutralSelected
            ? context.epColors.surfaceDisabled
            : context.epColors.volt,
        disabledColor: Colors.transparent,
        side: BorderSide(
          color: active && neutralSelected
              ? context.epColors.contentSecondary
              : active
              ? context.epColors.volt
              : context.epColors.border,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
  }
}

enum EpStatusPillTone { success, selected, warning, neutral }

/// Small, textual state marker. Color is never the only status signal.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = EpStatusPillTone.success,
  });

  final String label;
  final EpStatusPillTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (tone) {
      EpStatusPillTone.success => (
        context.epColors.successTint,
        context.epColors.success,
        context.epColors.success.withValues(alpha: .5),
      ),
      EpStatusPillTone.selected => (
        context.epColors.selected,
        context.epColors.ink,
        context.epColors.accent,
      ),
      EpStatusPillTone.warning => (
        context.epColors.warningTint,
        context.epColors.volt,
        context.epColors.volt,
      ),
      EpStatusPillTone.neutral => (
        context.epColors.raised,
        context.epColors.contentSecondary,
        context.epColors.border,
      ),
    };
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(
              context,
            ).textTheme.epChipLabel.copyWith(color: foreground, fontSize: 11),
          ),
        ),
      ),
    );
  }
}

/// The single high-energy callout a page may promote above its quiet cards.
class VoltStrip extends StatelessWidget {
  const VoltStrip({
    super.key,
    required this.kicker,
    required this.title,
    required this.meta,
    this.actionLabel,
    this.onAction,
  });

  final String kicker;
  final String title;
  final String meta;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.epColors.volt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kicker.toUpperCase(),
              style: Theme.of(context).textTheme.epSection.copyWith(
                color: context.epColors.dark,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.epPosterTitle.copyWith(color: context.epColors.dark),
            ),
            const SizedBox(height: 5),
            Text(
              meta,
              style: Theme.of(
                context,
              ).textTheme.epMeta.copyWith(color: context.epColors.dark),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: onAction,
                style: ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                  backgroundColor: WidgetStatePropertyAll(
                    context.epColors.dark,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? context.epColors.mute
                        : context.epColors.volt,
                  ),
                ),
                child: Text(actionLabel!.toUpperCase()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact, unchromed history line with an optional action.
class LedgerRow extends StatelessWidget {
  const LedgerRow({
    super.key,
    required this.title,
    this.details = const [],
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final List<String> details;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final description = [title, ...details].join(' · ');
    final content = Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 8)],
        Expanded(
          child: Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.epMeta,
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
    return Semantics(
      container: true,
      button: onTap != null,
      label: description,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Material(
          color: Colors.transparent,
          child: onTap == null
              ? Align(alignment: Alignment.centerLeft, child: content)
              : InkWell(onTap: onTap, child: content),
        ),
      ),
    );
  }
}

/// FREE / $n price tag (the spec's badgeStyle).
class PriceBadge extends StatelessWidget {
  final Gig gig;

  const PriceBadge(this.gig, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: gig.free ? Ep.brand : null,
        border: gig.free ? null : Border.all(color: context.epColors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        gig.priceLabel,
        style: Theme.of(context).textTheme.epLabel.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
          color: gig.free ? Colors.white : context.epColors.contentPrimary,
        ),
      ),
    );
  }
}

class _FlyerPatternPainter extends CustomPainter {
  final FlyerStyle style;
  final double scale;

  const _FlyerPatternPainter(this.style, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = style.patternColor;
    final pitch = style.pitch * scale;
    switch (style.pattern) {
      case FlyerPattern.scan:
        for (double y = 0; y < size.height; y += pitch) {
          canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
        }
      case FlyerPattern.dots:
        for (double y = 1; y < size.height; y += pitch) {
          for (double x = 1; x < size.width; x += pitch) {
            canvas.drawCircle(Offset(x, y), 1.2, paint);
          }
        }
      case FlyerPattern.hatch:
        // 45° bars: sweep the diagonal offset across both edges of the box.
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = pitch / 2;
        for (
          double d = -size.height;
          d < size.width + size.height;
          d += pitch
        ) {
          canvas.drawLine(
            Offset(d, 0),
            Offset(d + size.height, size.height),
            paint,
          );
        }
      case FlyerPattern.rays:
        final center = Offset(size.width / 2, size.height * .28);
        final reach = size.width + size.height;
        final wedge = style.pitch * math.pi / 180;
        for (double a = 0; a < 2 * math.pi; a += wedge) {
          canvas.drawPath(
            Path()
              ..moveTo(center.dx, center.dy)
              ..lineTo(
                center.dx + reach * math.cos(a),
                center.dy + reach * math.sin(a),
              )
              ..lineTo(
                center.dx + reach * math.cos(a + wedge / 2),
                center.dy + reach * math.sin(a + wedge / 2),
              )
              ..close(),
            paint,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_FlyerPatternPainter old) =>
      old.style != style || old.scale != scale;
}

class ClipTexture extends StatelessWidget {
  final Color bandColor;
  final double patternScale;

  const ClipTexture({
    super.key,
    required this.bandColor,
    this.patternScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final style = FlyerStyle(
      base: context.epColors.surface,
      patternColor: Ep.whiteA(.06),
      fg: context.epColors.contentPrimary,
      pattern: FlyerPattern.scan,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: context.epColors.surface),
        ColoredBox(color: bandColor.withValues(alpha: .14)),
        CustomPaint(painter: _FlyerPatternPainter(style, patternScale)),
      ],
    );
  }
}

/// Xeroxed-flyer block: solid base color under a faint print texture.
///
/// Rotation belongs only in an outer, explicitly decorative preview. Keeping
/// it out of this shared primitive makes functional artwork upright by default.
class FlyerBox extends StatelessWidget {
  final FlyerStyle style;
  final String? imageUrl;
  final double? width;
  final double? height;
  final double radius;
  final EdgeInsets padding;
  final Widget? child;
  final bool shadow;
  final bool scrim;

  /// Multiplies [FlyerStyle.pitch] so small swatches read as the same texture.
  final double patternScale;

  const FlyerBox({
    super.key,
    required this.style,
    this.imageUrl,
    this.width,
    this.height,
    this.radius = 6,
    this.padding = EdgeInsets.zero,
    this.child,
    this.shadow = true,
    this.scrim = false,
    this.patternScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: style.base,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .5),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl!.isEmpty
          ? CustomPaint(
              painter: _FlyerPatternPainter(style, patternScale),
              child: Padding(padding: padding, child: child),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                EpNetworkImage(
                  url: imageUrl,
                  fit: BoxFit.cover,
                  fallback: CustomPaint(
                    painter: _FlyerPatternPainter(style, patternScale),
                  ),
                ),
                if (scrim)
                  const DecoratedBox(
                    key: ValueKey('flyer-image-scrim'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xA8000000), Color(0xBD000000)],
                      ),
                    ),
                  ),
                Padding(padding: padding, child: child),
              ],
            ),
    );
  }
}

class GigFlyer extends StatelessWidget {
  final Gig gig;
  final FlyerStyle style;
  final double? width;
  final double? height;
  final double radius;
  final EdgeInsets padding;
  final Widget? child;
  final bool shadow;
  final bool scrim;
  final double patternScale;

  const GigFlyer(
    this.gig,
    this.style, {
    super.key,
    this.width,
    this.height,
    this.radius = 6,
    this.padding = EdgeInsets.zero,
    this.child,
    this.shadow = true,
    this.scrim = false,
    this.patternScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return FlyerBox(
      style: style,
      imageUrl: gig.flyKey == 'custom' ? gig.flyerUrl : null,
      width: width,
      height: height,
      radius: radius,
      padding: padding,
      shadow: shadow,
      scrim: scrim,
      patternScale: patternScale,
      child: child,
    );
  }
}

/// Upright shared profile treatment for people and bands.
class EpProfileAvatar extends StatelessWidget {
  const EpProfileAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.radius = 9,
    this.fontSize,
  });

  final String? name;
  final String? imageUrl;
  final double size;
  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final initials = profileInitials(name);
    final fallback = ColoredBox(
      color: Ep.brand,
      child: Center(
        child: initials == '??'
            ? Icon(Icons.person, size: size * .52, color: Colors.white)
            : Text(
                initials,
                style: Theme.of(context).textTheme.epLabel.copyWith(
                  color: Colors.white,
                  fontSize: fontSize ?? size * .34,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );

    return Semantics(
      image: true,
      label: name == null || name!.trim().isEmpty
          ? 'Profile avatar'
          : '${name!.trim()} avatar',
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox.square(
            dimension: size,
            child: EpNetworkImage(url: imageUrl, fallback: fallback),
          ),
        ),
      ),
    );
  }
}

/// The private fan-profile avatar treatment.
///
/// Keeping this separate from [BandAvatar] makes the fan fallback consistent
/// anywhere the personal identity appears, while uploaded photos still use the
/// same accessible network-image behavior as every other profile image.
class EpFanAvatar extends StatelessWidget {
  const EpFanAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.radius = 9,
    this.fontSize,
  });

  final String? name;
  final String? imageUrl;
  final double size;
  final double radius;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    return EpProfileAvatar(
      name: name,
      imageUrl: imageUrl,
      size: size,
      radius: radius,
      fontSize: fontSize,
    );
  }
}

class ProfileCompleteBadge extends StatelessWidget {
  const ProfileCompleteBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('profile-complete-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: context.epColors.success.withValues(alpha: .12),
        border: Border.all(
          color: context.epColors.success.withValues(alpha: .55),
        ),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'PROFILE COMPLETE',
        style: Theme.of(context).textTheme.epCaption.copyWith(
          color: context.epColors.success,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: .7,
        ),
      ),
    );
  }
}

/// Convenience adapter for existing band call sites.
class BandAvatar extends StatelessWidget {
  final Band band;
  final double size;
  final double radius;
  final double fontSize;

  const BandAvatar(
    this.band, {
    super.key,
    this.size = 40,
    this.radius = 9,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return EpProfileAvatar(
      name: band.name,
      imageUrl: band.profileImageUrl,
      size: size,
      radius: radius,
      fontSize: fontSize,
    );
  }
}

class CircleIconButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final Color? background;
  final bool bordered;
  final String? tooltip;

  const CircleIconButton({
    super.key,
    required this.onTap,
    this.icon = Icons.chevron_left,
    this.background,
    this.bordered = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedTooltip =
        tooltip ??
        switch (icon) {
          Icons.close => 'Close',
          _ => 'Back',
        };
    return IconButton(
      onPressed: onTap,
      tooltip: resolvedTooltip,
      style: ButtonStyle(
        fixedSize: WidgetStatePropertyAll(Size.square(48)),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? context.epColors.contentDisabled
              : context.epColors.contentPrimary,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return context.epColors.contentPrimary.withValues(alpha: .14);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return context.epColors.contentPrimary.withValues(alpha: .08);
          }
          return Colors.transparent;
        }),
        shape: WidgetStatePropertyAll(CircleBorder()),
      ),
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap == null
              ? context.epColors.surfaceDisabled
              : background ?? context.epColors.surface,
          shape: BoxShape.circle,
          border: bordered ? Border.all(color: context.epColors.border) : null,
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18),
      ),
    );
  }
}

enum EpButtonKind { filled, light, outline, ghost, disabled }

/// The spec's handful of button treatments.
class EpButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final EpButtonKind kind;
  final double fontSize;
  final EdgeInsets padding;

  const EpButton(
    this.label, {
    super.key,
    required this.onTap,
    this.kind = EpButtonKind.filled,
    this.fontSize = 13.5,
    this.padding = const EdgeInsets.symmetric(vertical: 15),
  });

  @override
  Widget build(BuildContext context) {
    final callback = kind == EpButtonKind.disabled ? null : onTap;
    final (Color background, Color foreground) = switch (kind) {
      EpButtonKind.light => (
        context.epColors.contentPrimary,
        context.epColors.background,
      ),
      EpButtonKind.filled ||
      EpButtonKind.outline ||
      EpButtonKind.ghost => (Ep.brand, Colors.white),
      EpButtonKind.disabled => (
        context.epColors.surfaceDisabled,
        context.epColors.contentDisabled,
      ),
    };
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
      padding: WidgetStatePropertyAll(padding),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? context.epColors.surfaceDisabled
            : background,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? context.epColors.contentDisabled
            : foreground,
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.epLabel.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      ),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: context.epColors.surfaceDisabled);
        }
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: context.epColors.contentPrimary, width: 2);
        }
        return switch (kind) {
          EpButtonKind.outline => BorderSide(
            color: context.epColors.accent,
            width: 1.5,
          ),
          EpButtonKind.ghost => BorderSide(color: context.epColors.border),
          _ => BorderSide.none,
        };
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    final button = switch (kind) {
      EpButtonKind.outline || EpButtonKind.ghost => OutlinedButton(
        onPressed: callback,
        style: style.copyWith(
          backgroundColor: WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? context.epColors.contentDisabled
                : kind == EpButtonKind.outline
                ? context.epColors.accent
                : context.epColors.contentPrimary,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
      _ => FilledButton(
        onPressed: callback,
        style: style,
        child: Text(label, textAlign: TextAlign.center),
      ),
    };
    return SizedBox(width: double.infinity, child: button);
  }
}

InputDecoration epInputDecoration(BuildContext context, String hint) =>
    InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: context.epColors.surface,
      isDense: true,
      constraints: const BoxConstraints(minHeight: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: context.epColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: context.epColors.accent, width: 2),
      ),
    );

InputDecoration epCollapsedInputDecoration(
  String hint, {
  TextStyle? hintStyle,
}) => InputDecoration.collapsed(hintText: hint, hintStyle: hintStyle).copyWith(
  // InputDecorationTheme supplies state-specific outline borders even when
  // InputDecoration.collapsed sets its fallback border to none.
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
);

/// Compact dashboard metric with a label, headline value, and caption.
class EpStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;
  final bool expand;

  const EpStatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final tile = EpCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      borderColor: context.epColors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 100;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height:
                    (compact ? 32 : 18) +
                    (textScale - 1).clamp(0, 1) * (compact ? 21 : 9),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    label.toUpperCase(),
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epChipLabel.copyWith(
                      fontSize: 11,
                      letterSpacing: compact ? 0 : 1.5,
                      color: context.epColors.mute,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.epDisplay.copyWith(fontSize: 22),
              ),
              if (caption != null && caption!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                SizedBox(
                  height:
                      (compact ? 48 : 32) +
                      (textScale - 1).clamp(0, 1) * (compact ? 42 : 28),
                  child: Text(
                    caption!,
                    maxLines: compact ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.epCaption,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
    return expand ? Expanded(child: tile) : tile;
  }
}

/// Labeled horizontal value bar scaled against a caller-supplied maximum.
class EpBar extends StatelessWidget {
  final String label;
  final num value;
  final num max;
  final String valueText;

  const EpBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.valueText,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0
        ? 0.0
        : (value.toDouble() / max.toDouble()).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.epCaption.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.epColors.contentSecondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.epCaption.copyWith(
                fontWeight: FontWeight.w800,
                color: context.epColors.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.epColors.surfaceDisabled,
            border: Border.all(color: context.epColors.border),
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(color: Ep.brand),
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline explanation for a server-suppressed analytics partition.
class EpSuppressedNote extends StatelessWidget {
  final String message;

  const EpSuppressedNote({super.key, this.message = 'Not enough data yet'});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.epCaption.copyWith(
        fontSize: 11.5,
        color: context.epColors.contentDisabled,
      ),
    );
  }
}

enum EpCardVariant { standard, raised, selected, disabled }

/// Semantic card container used across screens.
class EpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? borderColor;
  final VoidCallback? onTap;
  final EpCardVariant variant;

  const EpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
    this.borderColor,
    this.onTap,
    this.variant = EpCardVariant.standard,
  });

  @override
  Widget build(BuildContext context) {
    final (color, defaultBorder) = switch (variant) {
      EpCardVariant.standard => (
        context.epColors.surface,
        context.epColors.border,
      ),
      EpCardVariant.raised => (
        context.epColors.surfaceRaised,
        context.epColors.border,
      ),
      EpCardVariant.selected => (
        context.epColors.surfaceSelected,
        context.epColors.accent,
      ),
      EpCardVariant.disabled => (
        context.epColors.surfaceDisabled,
        context.epColors.surfaceDisabled,
      ),
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? defaultBorder),
    );
    final enabledOnTap = variant == EpCardVariant.disabled ? null : onTap;
    final content = Padding(padding: padding, child: child);

    return Semantics(
      container: true,
      button: onTap != null,
      enabled: onTap == null ? null : variant != EpCardVariant.disabled,
      selected: variant == EpCardVariant.selected ? true : null,
      child: Material(
        color: color,
        surfaceTintColor: Colors.transparent,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.infinity,
          child: enabledOnTap == null
              ? content
              : InkWell(
                  onTap: enabledOnTap,
                  customBorder: shape,
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// Dashed-border empty/placeholder box.
class DashedBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double radius;

  /// False lets the box shrink to its child — used for inline flyer chips.
  final bool expand;

  const DashedBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.radius = 13,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color ?? context.epColors.border, radius),
      child: Container(
        width: expand ? double.infinity : null,
        padding: padding,
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(.6, .6, size.width - 1.2, size.height - 1.2),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Play-button triangle.
class PlayTriangle extends StatelessWidget {
  final double size;
  final Color color;

  const PlayTriangle({super.key, this.size = 14, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.2),
      painter: _TrianglePainter(color),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  const _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

/// "Sam Reyes" → "SR"; single words take one letter; null/empty → "??".
String profileInitials(String? name) {
  final words = name
      ?.trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .toList();
  if (words == null || words.isEmpty) return '??';
  return words.map((word) => word[0]).join().toUpperCase();
}
