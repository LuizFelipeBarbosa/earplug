import 'package:flutter/material.dart';

import 'models.dart';

/// Flyer palettes and print textures. Legacy keys remain available for saved
/// gigs; [flyerPicks] offers the ink, panel, and accent palettes for new flyers.
const flyerStyles = <String, FlyerStyle>{
  'paper': FlyerStyle(
    base: Color(0xFFF2F2EF),
    patternColor: Color(0x0A000000),
    fg: Color(0xFF0A0A0B),
    pitch: 8,
  ),
  'blue': FlyerStyle(
    base: Color(0xFF8B5CFF),
    patternColor: Color(0x14000000),
    fg: Color(0xFF050506),
    pitch: 8,
  ),
  'black': FlyerStyle(
    base: Color(0xFF141416),
    patternColor: Color(0x0AF2F2EF),
    fg: Color(0xFFF2F2EF),
    pitch: 8,
  ),
  'yellow': FlyerStyle(
    base: Color(0xFFF2F2EF),
    patternColor: Color(0x0A000000),
    fg: Color(0xFF0A0A0B),
    pitch: 8,
  ),
  'bluetype': FlyerStyle(
    base: Color(0xFFF2F2EF),
    patternColor: Color(0x148B5CFF),
    fg: Color(0xFF6D3EF0),
    pitch: 8,
  ),
  // Legacy print textures, recolored to the current palette.
  'xerox': FlyerStyle(
    base: Color(0xFFF2F2EF),
    patternColor: Color(0x0A000000),
    fg: Color(0xFF0A0A0B),
    pitch: 8,
  ),
  'riso': FlyerStyle(
    base: Color(0xFFF2F2EF),
    patternColor: Color(0x338B5CFF),
    fg: Color(0xFF6D3EF0),
    pattern: FlyerPattern.dots,
    pitch: 6,
  ),
  'marquee': FlyerStyle(
    base: Color(0xFF141416),
    patternColor: Color(0x338B5CFF),
    fg: Color(0xFFF2F2EF),
    pattern: FlyerPattern.dots,
    pitch: 9,
  ),
  'blueprint': FlyerStyle(
    base: Color(0xFF8B5CFF),
    patternColor: Color(0x14000000),
    fg: Color(0xFF050506),
    pattern: FlyerPattern.hatch,
    pitch: 14,
  ),
  'sunburst': FlyerStyle(
    base: Color(0xFFF2F2EF),
    patternColor: Color(0x1A8B5CFF),
    fg: Color(0xFF0A0A0B),
    pattern: FlyerPattern.rays,
    pitch: 18,
  ),
  // Band-supplied art: dark plate the uploaded image sits on.
  'custom': FlyerStyle(
    base: Color(0xFF141416),
    patternColor: Color(0x00000000),
    fg: Color(0xFFF2F2EF),
  ),
  'ink': FlyerStyle(
    base: Color(0xFFF2F2EF),
    patternColor: Color(0x0A000000),
    fg: Color(0xFF0A0A0B),
    pitch: 8,
  ),
  'panel': FlyerStyle(
    base: Color(0xFF141416),
    patternColor: Color(0x0AF2F2EF),
    fg: Color(0xFFF2F2EF),
    pitch: 8,
  ),
  'accent': FlyerStyle(
    base: Color(0xFF8B5CFF),
    patternColor: Color(0x14000000),
    fg: Color(0xFF050506),
    pitch: 8,
  ),
};

/// Palettes offered by the gig editor, in swatch order.
const flyerPicks = ['ink', 'panel', 'accent'];
