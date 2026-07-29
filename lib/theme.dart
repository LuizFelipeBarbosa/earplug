import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// EarPlug design tokens — dark punk-flyer language from the design spec.
abstract final class Ep {
  static const bg = Color(0xFF0A0A0C);
  static const card = Color(0xFF121216);
  static const ink = Color(0xFFF4F4F0);
  static const blue = Color(0xFF1435F0);
  static const link = Color(0xFF7B8FFF);
  static const linkSoft = Color(0xFFB9C4FF);
  static const pageBackdrop = Color(0xFF17171B);

  /// Marks a field the user still has to fill in.
  static const required = Color(0xFFE4DC4A);

  /// Ink (off-white) at the given opacity — the spec leans on rgba(244,244,240,x).
  static Color inkA(double a) => ink.withValues(alpha: a);

  static Color whiteA(double a) => Colors.white.withValues(alpha: a);

  static Border hairline([double a = .1]) => Border.all(color: whiteA(a));
}

/// Archivo body text. Weights map straight from the spec's font-weight values.
TextStyle epText({
  double size = 13,
  FontWeight weight = FontWeight.w600,
  Color color = Ep.ink,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.archivo(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Archivo Black display type — titles, stats, flyer text.
TextStyle epDisplay({
  double size = 18,
  Color color = Ep.ink,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.archivoBlack(
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
    height: height ?? 1.1,
  );
}

ThemeData buildEpTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Ep.bg,
    colorScheme: const ColorScheme.dark(
      primary: Ep.blue,
      surface: Ep.bg,
      onSurface: Ep.ink,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
  return base.copyWith(
    textTheme: GoogleFonts.archivoTextTheme(base.textTheme),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Ep.ink,
      selectionColor: Ep.blue.withValues(alpha: .4),
      selectionHandleColor: Ep.blue,
    ),
  );
}
