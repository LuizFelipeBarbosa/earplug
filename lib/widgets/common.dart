import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../date_names.dart';
import '../initials.dart';
import '../models.dart';
import '../services/image_url.dart';
import '../theme.dart';
import 'ep_rows.dart';
import 'ep_text.dart';

/// Top padding for screen headers: status bar / notch plus breathing room.
double headerTopPad(BuildContext context) =>
    EpLayout.isDesktop(context) ? 28 : MediaQuery.paddingOf(context).top + 22;

/// Bottom inset used by scrollables so content clears the tab bar.
const double tabBarClearance = EpLayout.tabBarHeight + 32;

double actionBarClearance(BuildContext context) =>
    EpLayout.stackActions(context) ? 200 : 112;

/// The fixed bar across the top of a screen: status-bar clearance, the page
/// gutters and a hairline underneath.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.child,
    this.bottomPadding = 16,
    this.filled = true,
  });

  final Widget child;
  final double bottomPadding;

  /// Paints the page background behind the bar. Off where the screen's own
  /// scaffold already supplies it.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    // RootShell supplies the 28px desktop shell inset; mobile screens need
    // the full status-bar-aware header offset here.
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        EpLayout.isDesktop(context) ? 0 : headerTopPad(context),
        EpLayout.gutter,
        bottomPadding,
      ),
      decoration: BoxDecoration(
        color: filled ? context.epColors.background : null,
        border: Border(bottom: BorderSide(color: context.epColors.line)),
      ),
      child: child,
    );
  }
}

/// A pushed screen's title row: the back pill, the page heading and an
/// optional trailing control placed directly after the title.
class EpBackHeading extends StatelessWidget {
  const EpBackHeading({
    super.key,
    required this.title,
    required this.backKey,
    required this.onBack,
    this.backLabel = 'Back',
    this.trailing,
  });

  final String title;
  final Key backKey;
  final VoidCallback? onBack;
  final String backLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        EpIconPill(
          key: backKey,
          icon: Icons.arrow_back,
          semanticLabel: backLabel,
          onPressed: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.epPageHeading),
        ),
        ?trailing,
      ],
    );
  }
}

/// A lone back pill under the status bar, inset by the page gutters.
class EpBackBar extends StatelessWidget {
  const EpBackBar({super.key, required this.controlKey, required this.onBack});

  final Key controlKey;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        EpLayout.gutter,
        EpLayout.isDesktop(context) ? 0 : headerTopPad(context),
        EpLayout.gutter,
        0,
      ),
      child: Row(
        children: [
          EpIconPill(
            key: controlKey,
            icon: Icons.arrow_back,
            semanticLabel: 'Back',
            onPressed: onBack,
          ),
        ],
      ),
    );
  }
}

class EpNetworkImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final Widget fallback;

  /// Requested decode dimensions in logical pixels.
  final int? cacheWidth;
  final int? cacheHeight;

  const EpNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    required this.fallback,
    this.cacheWidth,
    this.cacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return fallback;
    final rawUrl = url!;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final physicalCacheWidth = !kIsWeb && cacheWidth != null
        ? (cacheWidth! * dpr).round()
        : null;
    final physicalCacheHeight = !kIsWeb && cacheHeight != null
        ? (cacheHeight! * dpr).round()
        : null;
    final imageUrl = kIsWeb && cacheWidth != null
        ? displayImageUrl(
            rawUrl,
            width: cacheWidth!,
            height: cacheHeight,
            base: Uri.base,
            devicePixelRatio: dpr,
          )
        : rawUrl;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 180),
      memCacheWidth: physicalCacheWidth,
      memCacheHeight: physicalCacheHeight,
      maxWidthDiskCache: physicalCacheWidth,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => imageUrl == rawUrl
          ? fallback
          : CachedNetworkImage(
              imageUrl: rawUrl,
              fit: fit,
              fadeInDuration: const Duration(milliseconds: 180),
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}

/// A date-first visual anchor for event and history rows.
class DateBlock extends StatelessWidget {
  /// Zero-padded day over the three-letter month, e.g. "07" / "SEP".
  DateBlock.forDate(DateTime date, {super.key, this.semanticLabel})
    : day = date.day.toString().padLeft(2, '0'),
      month = monthNamesUpper[date.month - 1];

  final String day;
  final String month;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? '${month.trim()} ${day.trim()}',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 40,
          child: MediaQuery.withNoTextScaling(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  day.trim().toUpperCase(),
                  semanticsLabel: day,
                  style: Theme.of(context).textTheme.epPosterTitle.copyWith(
                    color: context.epColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  month.trim().toUpperCase(),
                  semanticsLabel: month,
                  style: Theme.of(
                    context,
                  ).textTheme.epSection.copyWith(color: context.epColors.muted),
                ),
              ],
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
  final bool readOnly;
  final VoidCallback? onRemoved;
  final String? semanticLabel;

  const EpChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.ghost = false,
    this.neutralSelected = false,
    this.readOnly = false,
    this.onRemoved,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || onRemoved != null;
    final locked = active && !enabled && !readOnly;
    final palette = context.epColors;
    final transparent = palette.background.withValues(alpha: 0);
    final textStyle = Theme.of(context).textTheme.epChipLabel.copyWith(
      color: !enabled && !active && !readOnly
          ? palette.contentDisabled
          : active
          ? neutralSelected
                ? palette.ink
                : palette.onAccent
          : palette.ink,
    );
    final selectedColor = neutralSelected
        ? palette.surfaceSelected
        : palette.ink;
    final side = active ? BorderSide.none : BorderSide(color: palette.outline);
    final labelText = Text(
      label.toUpperCase(),
      semanticsLabel: semanticLabel ?? label,
      style: textStyle,
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
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Center(
                child: DashedBox(
                  expand: false,
                  radius: EpLayout.pillRadius,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 20),
                    child: labelText,
                  ),
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
          labelPadding: EdgeInsets.zero,
          label: labelText,
          selected: active,
          onPressed: onTap,
          onDeleted: onRemoved,
          deleteIcon: Icon(Icons.close, size: 16),
          deleteIconColor: textStyle.color,
          showCheckmark: false,
          backgroundColor: transparent,
          selectedColor: selectedColor,
          disabledColor: transparent,
          side: side,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      );
    }
    final chip = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: FilterChip(
        labelPadding: EdgeInsets.zero,
        label: labelText,
        selected: active,
        // Keep RawChip enabled so it does not fade the selected label.
        onSelected: locked || readOnly
            ? (_) {}
            : onTap == null
            ? null
            : (_) => onTap!(),
        onDeleted: onRemoved,
        deleteIcon: Icon(Icons.close, size: 16),
        deleteIconColor: textStyle.color,
        showCheckmark: false,
        backgroundColor: transparent,
        selectedColor: selectedColor,
        disabledColor: transparent,
        side: side,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
    if (locked || readOnly) {
      return IgnorePointer(child: ExcludeFocus(child: chip));
    }
    return chip;
  }
}

/// The accent callout a page may promote above its quiet panels.
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
        padding: const EdgeInsets.all(20),
        color: context.epColors.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kicker.toUpperCase(),
              semanticsLabel: kicker,
              style: Theme.of(
                context,
              ).textTheme.epSection.copyWith(color: context.epColors.onAccent),
            ),
            const SizedBox(height: 6),
            Text(
              title.toUpperCase(),
              semanticsLabel: title,
              style: Theme.of(context).textTheme
                  .epDisplayAt(40)
                  .copyWith(color: context.epColors.onAccent, height: .9),
            ),
            const SizedBox(height: 5),
            Text(
              meta.toUpperCase(),
              semanticsLabel: meta,
              style: Theme.of(
                context,
              ).textTheme.epMeta.copyWith(color: context.epColors.onAccent),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: onAction,
                style: ButtonStyle(
                  minimumSize: WidgetStatePropertyAll(Size(48, 48)),
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  shape: WidgetStatePropertyAll(StadiumBorder()),
                  textStyle: WidgetStatePropertyAll(
                    Theme.of(context).textTheme.epLabel,
                  ),
                  backgroundColor: WidgetStatePropertyAll(
                    context.epColors.background,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.disabled)
                        ? context.epColors.contentDisabled
                        : context.epColors.ink,
                  ),
                ),
                child: Text(
                  actionLabel!.toUpperCase(),
                  semanticsLabel: actionLabel,
                ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.epBody.copyWith(color: context.epColors.ink),
              ),
              if (details.isNotEmpty)
                Text(
                  details.join(' · ').toUpperCase(),
                  semanticsLabel: details.join(' · '),
                  style: Theme.of(context).textTheme.epMeta,
                ),
            ],
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: EpRow(
            minHeight: 47,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: content,
          ),
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
    this.radius = 0,
    this.padding = EdgeInsets.zero,
    this.child,
    this.shadow = false,
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
                  color: context.epColors.background.withValues(alpha: .5),
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
          : RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EpNetworkImage(
                    url: imageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: (width ?? 448).round(),
                    cacheHeight: height?.round(),
                    fallback: CustomPaint(
                      painter: _FlyerPatternPainter(style, patternScale),
                    ),
                  ),
                  if (scrim)
                    const DecoratedBox(
                      key: ValueKey('flyer-image-scrim'),
                      decoration: BoxDecoration(gradient: Ep.bannerScrim),
                    ),
                  Padding(padding: padding, child: child),
                ],
              ),
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
    this.radius = 0,
    this.padding = EdgeInsets.zero,
    this.child,
    this.shadow = false,
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

/// The fan-profile avatar: an uploaded photo, or initials on a square panel.
///
/// Kept separate from [BandAvatar] so the personal-identity fallback stays
/// consistent everywhere it appears.
class EpFanAvatar extends StatelessWidget {
  const EpFanAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
  });

  final String? name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = initialsFirstWords(name);
    final fallback = ColoredBox(
      color: context.epColors.panel,
      child: Center(
        child: initials == '??'
            ? Icon(
                Icons.person,
                size: size * .52,
                color: context.epColors.muted,
              )
            : Text(
                initials.toUpperCase(),
                semanticsLabel: initials,
                style: Theme.of(context).textTheme
                    .epDisplayAt(size * .45)
                    .copyWith(color: context.epColors.ink),
              ),
      ),
    );

    return Semantics(
      image: true,
      label: name == null || name!.trim().isEmpty
          ? 'Profile avatar'
          : '${name!.trim()} avatar',
      child: ExcludeSemantics(
        child: ClipRect(
          clipBehavior: Clip.antiAlias,
          child: SizedBox.square(
            dimension: size,
            child: EpNetworkImage(
              url: imageUrl,
              cacheWidth: size.round(),
              cacheHeight: size.round(),
              fallback: fallback,
            ),
          ),
        ),
      ),
    );
  }
}

/// Name over the optional scene and member-since captions, as on the fan
/// profile header and its edit-screen preview.
class FanIdentityLines extends StatelessWidget {
  const FanIdentityLines({
    super.key,
    required this.name,
    required this.homeLocation,
    required this.createdAt,
    required this.nameKey,
    required this.sceneKey,
    required this.sinceKey,
    this.showUnknownScene = false,
  });

  final String name;
  final FanCity? homeLocation;
  final DateTime? createdAt;
  final Key nameKey;
  final Key sceneKey;
  final Key sinceKey;

  /// Renders a muted "Scene unknown" line when [homeLocation] is null.
  final bool showUnknownScene;

  @override
  Widget build(BuildContext context) {
    final caption = Theme.of(context).textTheme.epCaption;
    final palette = context.epColors;
    final Widget? scene;
    if (homeLocation case final FanCity city) {
      scene = Text(
        '${city.label} scene',
        key: sceneKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: caption.copyWith(color: palette.ink),
      );
    } else if (showUnknownScene) {
      scene = Text(
        'Scene unknown',
        key: sceneKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: caption.copyWith(color: palette.muted),
      );
    } else {
      scene = null;
    }
    final Widget? since;
    if (createdAt case final date?) {
      since = Text(
        'Since ${monthNames[date.month - 1]} ${date.year}',
        key: sinceKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: caption.copyWith(color: palette.muted),
      );
    } else {
      since = null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EpDisplay(name, key: nameKey, size: 20, keepCase: true),
        if (scene != null || since != null) const SizedBox(height: 2),
        ?scene,
        ?since,
      ],
    );
  }
}

/// Convenience adapter for existing band call sites.
class BandAvatar extends StatelessWidget {
  final Band band;
  final double size;

  const BandAvatar(this.band, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return EpFanAvatar(
      name: band.name,
      imageUrl: band.profileImageUrl,
      size: size,
    );
  }
}

class CircleIconButton extends StatelessWidget {
  final VoidCallback? onTap;
  final IconData icon;
  final String? tooltip;

  const CircleIconButton({
    super.key,
    required this.onTap,
    this.icon = Icons.arrow_back,
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
              : context.epColors.ink,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return context.epColors.ink.withValues(alpha: .14);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return context.epColors.ink.withValues(alpha: .08);
          }
          return context.epColors.background.withValues(alpha: 0);
        }),
        shape: WidgetStatePropertyAll(CircleBorder()),
      ),
      icon: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.epColors.outline),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 16),
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
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(vertical: 15),
  });

  @override
  Widget build(BuildContext context) {
    final callback = kind == EpButtonKind.disabled ? null : onTap;
    final palette = context.epColors;
    final transparent = palette.background.withValues(alpha: 0);
    final (Color background, Color foreground) = switch (kind) {
      EpButtonKind.light => (palette.ink, palette.onAccent),
      EpButtonKind.filled => (palette.accent, palette.onAccent),
      EpButtonKind.outline || EpButtonKind.ghost => (transparent, palette.ink),
      EpButtonKind.disabled => (transparent, palette.contentDisabled),
    };
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, 48)),
      padding: WidgetStatePropertyAll(padding),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.disabled) ? transparent : background,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? palette.contentDisabled
            : foreground,
      ),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.epLabel.copyWith(fontSize: fontSize),
      ),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: palette.outline);
        }
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: palette.ink, width: 2);
        }
        return switch (kind) {
          EpButtonKind.outline => BorderSide(color: palette.outline),
          _ => BorderSide.none,
        };
      }),
      shape: WidgetStatePropertyAll(StadiumBorder()),
    );
    final text = Text(
      label.toUpperCase(),
      semanticsLabel: label,
      textAlign: TextAlign.center,
    );
    final button = switch (kind) {
      EpButtonKind.outline || EpButtonKind.ghost => OutlinedButton(
        onPressed: callback,
        style: style,
        child: text,
      ),
      _ => FilledButton(onPressed: callback, style: style, child: text),
    };
    return Semantics(
      enabled: callback != null,
      child: SizedBox(width: double.infinity, child: button),
    );
  }
}

/// Text boxes inherit their padding, surface, and all state borders from the
/// shared theme, including when they appear in a dialog or sheet.
InputDecoration epInputDecoration(BuildContext context, String hint) =>
    InputDecoration(hintText: hint);

/// Unchromed dashboard metric with a headline value, label, and caption.
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
    final tile = Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 100;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.toUpperCase(),
                semanticsLabel: value,
                style: Theme.of(context).textTheme.epDisplayAt(32),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (compact ? 32 : 18) +
                      (textScale - 1).clamp(0, 1) * (compact ? 21 : 9),
                ),
                child: Text(
                  label.toUpperCase(),
                  semanticsLabel: label,
                  style: Theme.of(
                    context,
                  ).textTheme.epSection.copyWith(color: context.epColors.muted),
                ),
              ),
              if (caption != null && caption!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        (compact ? 48 : 32) +
                        (textScale - 1).clamp(0, 1) * (compact ? 42 : 28),
                  ),
                  child: Text(
                    caption!,
                    style: Theme.of(
                      context,
                    ).textTheme.epBody.copyWith(color: context.epColors.muted),
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
    this.padding = const EdgeInsets.all(16),
    this.radius = EpLayout.cardRadius,
    this.borderColor,
    this.onTap,
    this.variant = EpCardVariant.standard,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (variant) {
      EpCardVariant.standard => context.epColors.panel,
      EpCardVariant.raised => context.epColors.surfaceRaised,
      EpCardVariant.selected => context.epColors.surfaceSelected,
      EpCardVariant.disabled => context.epColors.surfaceDisabled,
    };
    final border =
        borderColor ??
        (variant == EpCardVariant.selected ? context.epColors.accent : null);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border == null ? BorderSide.none : BorderSide(color: border),
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
        surfaceTintColor: context.epColors.background.withValues(alpha: 0),
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
    this.radius = 0,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color ?? context.epColors.outline, radius),
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
  final Color? color;

  const PlayTriangle({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.2),
      painter: _TrianglePainter(color ?? context.epColors.ink),
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
