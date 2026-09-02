import 'package:flutter/material.dart';

enum BrandGlyph {
  instagram(IconData(0xE900)),
  bandcamp(IconData(0xE901)),
  youtube(IconData(0xE902));

  const BrandGlyph(this.data);

  final IconData data;
}

class BrandIcon extends Icon {
  BrandIcon({
    super.key,
    required this.glyph,
    double size = 18,
    required Color color,
  }) : _size = size,
       _color = color,
       super(glyph.data, size: size, color: color);

  final BrandGlyph glyph;
  final double _size;
  final Color _color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(_size),
      painter: _BrandIconPainter(glyph: glyph, color: _color),
    );
  }
}

class _BrandIconPainter extends CustomPainter {
  const _BrandIconPainter({required this.glyph, required this.color});

  final BrandGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    switch (glyph) {
      case BrandGlyph.instagram:
        _paintInstagram(canvas, size);
      case BrandGlyph.bandcamp:
        _paintBandcamp(canvas, size);
      case BrandGlyph.youtube:
        _paintYouTube(canvas, size);
    }
  }

  void _paintInstagram(Canvas canvas, Size size) {
    final shortestSide = size.shortestSide;
    final strokeWidth = shortestSide * 0.09;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final bounds = Offset.zero & size;
    final insetBounds = bounds.deflate(strokeWidth / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        insetBounds,
        Radius.circular(shortestSide * 0.24),
      ),
      outline,
    );
    canvas.drawCircle(bounds.center, shortestSide * 0.19, outline);
    canvas.drawCircle(
      Offset(size.width * 0.73, size.height * 0.27),
      shortestSide * 0.055,
      Paint()..color = color,
    );
  }

  void _paintBandcamp(Canvas canvas, Size size) {
    final shortestSide = size.shortestSide;
    final strokeWidth = shortestSide * 0.09;
    final bounds = Offset.zero & size;
    canvas.drawCircle(
      bounds.center,
      (shortestSide - strokeWidth) / 2,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final mark = Path()
      ..moveTo(size.width * 0.36, size.height * 0.34)
      ..lineTo(size.width * 0.76, size.height * 0.34)
      ..lineTo(size.width * 0.64, size.height * 0.66)
      ..lineTo(size.width * 0.24, size.height * 0.66)
      ..close();
    canvas.drawPath(mark, Paint()..color = color);
  }

  void _paintYouTube(Canvas canvas, Size size) {
    final shortestSide = size.shortestSide;
    final strokeWidth = shortestSide * 0.09;
    final bounds = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds.deflate(strokeWidth / 2),
        Radius.circular(shortestSide * 0.22),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final play = Path()
      ..moveTo(size.width * 0.43, size.height * 0.32)
      ..lineTo(size.width * 0.72, size.height * 0.5)
      ..lineTo(size.width * 0.43, size.height * 0.68)
      ..close();
    canvas.drawPath(play, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BrandIconPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.color != color;
  }
}
