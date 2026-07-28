import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Top padding for screen headers: status bar / notch plus breathing room.
double headerTopPad(BuildContext context) =>
    math.max(MediaQuery.paddingOf(context).top, 24) + 10;

/// Bottom inset used by scrollables so content clears the floating tab bar.
const double tabBarClearance = 96;

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
  final VoidCallback onTap;

  const EpChip({super.key, required this.label, required this.active, required this.onTap});

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
            color: active ? Colors.white : Ep.inkA(.65),
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

class _StripePainter extends CustomPainter {
  final Color stripe;

  const _StripePainter(this.stripe);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = stripe;
    for (double y = 0; y < size.height; y += 5) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.stripe != stripe;
}

/// Xeroxed-flyer block: solid base color with faint horizontal scan stripes,
/// slightly rotated. The visual signature of the whole app.
class FlyerBox extends StatelessWidget {
  final FlyerStyle style;
  final double? width;
  final double? height;
  final double rotationDeg;
  final double radius;
  final EdgeInsets padding;
  final Widget? child;
  final bool shadow;

  const FlyerBox({
    super.key,
    required this.style,
    this.width,
    this.height,
    this.rotationDeg = 0,
    this.radius = 6,
    this.padding = EdgeInsets.zero,
    this.child,
    this.shadow = true,
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
            ? [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 10, offset: const Offset(0, 3))]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _StripePainter(style.stripe),
        child: Padding(padding: padding, child: child),
      ),
    );
    if (rotationDeg != 0) {
      box = Transform.rotate(angle: rotationDeg * math.pi / 180, child: box);
    }
    return box;
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
    return Transform.rotate(
      angle: rotationDeg * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: band.color,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Text(band.initials, style: epDisplay(size: fontSize, color: Ep.bg)),
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
      EpButtonKind.outline => (null, Ep.link, Border.all(color: Ep.blue, width: 1.5)),
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
              ? [BoxShadow(color: Ep.blue.withValues(alpha: .45), blurRadius: 22, offset: const Offset(0, 6))]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: epText(size: fontSize, weight: FontWeight.w900, letterSpacing: .8, color: fg),
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
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card);
  }
}

/// Dashed-border empty/placeholder box.
class DashedBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const DashedBox({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(Ep.whiteA(.18)),
      child: Container(width: double.infinity, padding: padding, child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(.6, .6, size.width - 1.2, size.height - 1.2),
      const Radius.circular(13),
    );
    final path = Path()..addRRect(rrect);
    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// Play-button triangle.
class PlayTriangle extends StatelessWidget {
  final double size;
  final Color color;

  const PlayTriangle({super.key, this.size = 14, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(size, size * 1.2), painter: _TrianglePainter(color));
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
