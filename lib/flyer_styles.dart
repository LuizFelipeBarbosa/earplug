import 'package:flutter/material.dart';

import 'models.dart';

/// The flyer presses a gig can be printed on. The first five keys are
/// legacy styles that seeded gigs still reference; `flyerPicks` lists the
/// presses a band chooses from when creating a gig.
const flyerStyles = <String, FlyerStyle>{
  'paper': FlyerStyle(
    base: Color(0xFFF4F4F0),
    patternColor: Color(0x0D000000),
    fg: Color(0xFF111114),
  ),
  'blue': FlyerStyle(
    base: Color(0xFF1435F0),
    patternColor: Color(0x1F000000),
    fg: Color(0xFFFFFFFF),
  ),
  'black': FlyerStyle(
    base: Color(0xFF141418),
    patternColor: Color(0x0DFFFFFF),
    fg: Color(0xFFF4F4F0),
  ),
  'yellow': FlyerStyle(
    base: Color(0xFFE4DC4A),
    patternColor: Color(0x0F000000),
    fg: Color(0xFF111114),
  ),
  'bluetype': FlyerStyle(
    base: Color(0xFFF4F4F0),
    patternColor: Color(0x141435F0),
    fg: Color(0xFF1435F0),
  ),
  // The five presses a band picks from when creating a gig.
  'xerox': FlyerStyle(
    base: Color(0xFFF4F4F0),
    patternColor: Color(0x0E000000),
    fg: Color(0xFF111114),
  ),
  'riso': FlyerStyle(
    base: Color(0xFFF4F4F0),
    patternColor: Color(0x6BF0456B),
    fg: Color(0xFF1435F0),
    pattern: FlyerPattern.dots,
    pitch: 6,
  ),
  'marquee': FlyerStyle(
    base: Color(0xFF141418),
    patternColor: Color(0x80E4DC4A),
    fg: Color(0xFFE4DC4A),
    pattern: FlyerPattern.dots,
    pitch: 9,
  ),
  'blueprint': FlyerStyle(
    base: Color(0xFF1435F0),
    patternColor: Color(0x14FFFFFF),
    fg: Color(0xFFF4F4F0),
    pattern: FlyerPattern.hatch,
    pitch: 14,
  ),
  'sunburst': FlyerStyle(
    base: Color(0xFFF2EE9E),
    patternColor: Color(0xFFE4DC4A),
    fg: Color(0xFF111114),
    pattern: FlyerPattern.rays,
    pitch: 18,
  ),
  // Band-supplied art: dark plate the uploaded image sits on.
  'custom': FlyerStyle(
    base: Color(0xFF141418),
    patternColor: Color(0x00000000),
    fg: Color(0xFFF4F4F0),
  ),
};

/// Presses offered by the gig-create flyer picker, in swatch order.
const flyerPicks = [
  'xerox',
  'riso',
  'marquee',
  'blueprint',
  'sunburst',
];
