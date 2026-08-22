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
      style: epText(
        size: 11,
        weight: FontWeight.w800,
        letterSpacing: 1.4,
        color: blue ? Ep.link : Ep.inkA(.5),
      ),
    );
  }
}

/// Rounded filter/selection chip (the spec's chipStyle).
class EpChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const EpChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Ep.blue : null,
          border: Border.all(color: active ? Ep.blue : Ep.whiteA(.2)),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label.toUpperCase(),
          style: epText(
            size: 11,
            weight: FontWeight.w800,
            letterSpacing: .5,
            color: active ? Colors.white : Ep.inkA(onTap == null ? .3 : .65),
          ),
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
        color: gig.free ? Ep.blue : null,
        border: gig.free ? null : Border.all(color: Ep.whiteA(.3)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        gig.priceLabel,
        style: epText(
          size: 10,
          weight: FontWeight.w900,
          letterSpacing: .8,
          color: gig.free ? Colors.white : Ep.inkA(.85),
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
      base: Ep.card,
      patternColor: Ep.whiteA(.06),
      fg: Ep.ink,
      pattern: FlyerPattern.scan,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Ep.card),
        ColoredBox(color: bandColor.withValues(alpha: .14)),
        CustomPaint(painter: _FlyerPatternPainter(style, patternScale)),
      ],
    );
  }
}

/// Xeroxed-flyer block: solid base color under a faint print texture, slightly
/// rotated. The visual signature of the whole app.
class FlyerBox extends StatelessWidget {
  final FlyerStyle style;
  final String? imageUrl;
  final double? width;
  final double? height;
  final double rotationDeg;
  final double radius;
  final EdgeInsets padding;
  final Widget? child;
  final bool shadow;

  /// Multiplies [FlyerStyle.pitch] so small swatches read as the same texture.
  final double patternScale;

  const FlyerBox({
    super.key,
    required this.style,
    this.imageUrl,
    this.width,
    this.height,
    this.rotationDeg = 0,
    this.radius = 6,
    this.padding = EdgeInsets.zero,
    this.child,
    this.shadow = true,
    this.patternScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    Widget box = Container(
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
                Padding(padding: padding, child: child),
              ],
            ),
    );
    if (rotationDeg != 0) {
      box = Transform.rotate(angle: rotationDeg * math.pi / 180, child: box);
    }
    return box;
  }
}

class GigFlyer extends StatelessWidget {
  final Gig gig;
  final FlyerStyle style;
  final double? width;
  final double? height;
  final double rotationDeg;
  final double radius;
  final EdgeInsets padding;
  final Widget? child;
  final bool shadow;
  final double patternScale;

  const GigFlyer(
    this.gig,
    this.style, {
    super.key,
    this.width,
    this.height,
    this.rotationDeg = 0,
    this.radius = 6,
    this.padding = EdgeInsets.zero,
    this.child,
    this.shadow = true,
    this.patternScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return FlyerBox(
      style: style,
      imageUrl: gig.flyKey == 'custom' ? gig.flyerUrl : null,
      width: width,
      height: height,
      rotationDeg: rotationDeg,
      radius: radius,
      padding: padding,
      shadow: shadow,
      patternScale: patternScale,
      child: child,
    );
  }
}

/// Rotated square initials tile used everywhere a band appears.
class BandAvatar extends StatelessWidget {
  final Band band;
  final double size;
  final double radius;
  final double fontSize;
  final double rotationDeg;

  const BandAvatar(
    this.band, {
    super.key,
    this.size = 40,
    this.radius = 9,
    this.fontSize = 14,
    this.rotationDeg = -3,
  });

  @override
  Widget build(BuildContext context) {
    final square = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: band.color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        band.initials,
        style: epDisplay(size: fontSize, color: Ep.bg),
      ),
    );
    if (band.heroUrl == null || band.heroUrl!.isEmpty) {
      return Transform.rotate(
        angle: rotationDeg * math.pi / 180,
        child: square,
      );
    }
    return Transform.rotate(
      angle: rotationDeg * math.pi / 180,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: EpNetworkImage(url: band.heroUrl, fallback: square),
        ),
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color background;
  final bool bordered;

  const CircleIconButton({
    super.key,
    required this.onTap,
    this.icon = Icons.chevron_left,
    this.background = Ep.card,
    this.bordered = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: bordered ? Border.all(color: Ep.whiteA(.14)) : null,
        ),
        child: Icon(icon, size: 20, color: Colors.white),
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
  final bool glow;

  const EpButton(
    this.label, {
    super.key,
    required this.onTap,
    this.kind = EpButtonKind.filled,
    this.fontSize = 13.5,
    this.padding = const EdgeInsets.symmetric(vertical: 15),
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final (Color? bg, Color fg, Border? border) = switch (kind) {
      EpButtonKind.filled => (Ep.blue, Colors.white, null),
      EpButtonKind.light => (Ep.ink, Ep.bg, null),
      EpButtonKind.outline => (
        null,
        Ep.link,
        Border.all(color: Ep.blue, width: 1.5),
      ),
      EpButtonKind.ghost => (null, Ep.ink, Border.all(color: Ep.whiteA(.3))),
      EpButtonKind.disabled => (Ep.whiteA(.08), Ep.inkA(.35), null),
    };
    return GestureDetector(
      onTap: kind == EpButtonKind.disabled ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: padding,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          border: border,
          borderRadius: BorderRadius.circular(12),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: Ep.blue.withValues(alpha: .45),
                    blurRadius: 22,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: epText(
            size: fontSize,
            weight: FontWeight.w900,
            letterSpacing: .8,
            color: fg,
          ),
        ),
      ),
    );
  }
}

InputDecoration epInputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: epText(size: 14, color: Ep.inkA(.35)),
  filled: true,
  fillColor: Ep.card,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: Ep.whiteA(.16)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: Ep.whiteA(.3)),
  ),
);

/// Compact dashboard metric with a label, headline value, and caption.
class EpStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String caption;

  const EpStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: EpCard(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
        radius: 13,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: epText(
                size: 9.5,
                weight: FontWeight.w800,
                letterSpacing: 1,
                color: Ep.inkA(.45),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: epDisplay(size: 22),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: epText(size: 10, weight: FontWeight.w800, color: Ep.link),
            ),
          ],
        ),
      ),
    );
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
                style: epText(
                  size: 11,
                  weight: FontWeight.w800,
                  color: Ep.inkA(.7),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              valueText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: epText(size: 11, weight: FontWeight.w800, color: Ep.link),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Ep.whiteA(.06),
            border: Ep.hairline(),
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fraction,
            heightFactor: 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(color: Ep.blue),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-part horizontal bar with a compact new/returning legend.
class EpStackedBar extends StatelessWidget {
  final num newValue;
  final num returningValue;
  final String newLabel;
  final String returningLabel;

  const EpStackedBar({
    super.key,
    required this.newValue,
    required this.returningValue,
    this.newLabel = 'NEW',
    this.returningLabel = 'RETURNING',
  });

  @override
  Widget build(BuildContext context) {
    final safeNew = math.max(0.0, newValue.toDouble());
    final safeReturning = math.max(0.0, returningValue.toDouble());
    final total = safeNew + safeReturning;
    final newFlex = total == 0
        ? 0
        : math.max(1, (safeNew / total * 1000).round());
    final returningFlex = total == 0
        ? 0
        : math.max(1, (safeReturning / total * 1000).round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 8,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Ep.whiteA(.06),
            border: Ep.hairline(),
            borderRadius: BorderRadius.circular(99),
          ),
          child: total == 0
              ? null
              : Row(
                  children: [
                    if (safeNew > 0)
                      Expanded(
                        flex: newFlex,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(color: Ep.blue),
                        ),
                      ),
                    if (safeReturning > 0)
                      Expanded(
                        flex: returningFlex,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(color: Ep.link),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Ep.blue,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              newLabel,
              style: epText(
                size: 9.5,
                weight: FontWeight.w800,
                color: Ep.inkA(.5),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Ep.link,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              returningLabel,
              style: epText(
                size: 9.5,
                weight: FontWeight.w800,
                color: Ep.inkA(.5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Inline explanation for a server-suppressed analytics partition.
class EpSuppressedNote extends StatelessWidget {
  final String message;

  const EpSuppressedNote({super.key, this.message = '— not enough data yet'});

  @override
  Widget build(BuildContext context) {
    return Text(message, style: epText(size: 11.5, color: Ep.inkA(.4)));
  }
}

/// Dark card container used across screens.
class EpCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? borderColor;
  final VoidCallback? onTap;

  const EpCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Ep.card,
        border: Border.all(color: borderColor ?? Ep.whiteA(.1)),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
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
      painter: _DashedBorderPainter(color ?? Ep.whiteA(.18), radius),
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
