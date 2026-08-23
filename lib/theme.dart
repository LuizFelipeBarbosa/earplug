import 'package:flutter/material.dart';

/// EarPlug's semantic design tokens.
///
/// Screens should choose a token for its purpose, rather than creating a
/// lighter or darker color with opacity. Artwork and readability overlays are
/// the intentional exceptions.
abstract final class Ep {
  // Brand.
  static const brand = Color(0xFF1435F0);
  static const accent = Color(0xFF7B8FFF);

  // Surfaces.
  static const background = Color(0xFF0A0A0C);
  static const surface = Color(0xFF17191F);
  static const surfaceRaised = Color(0xFF22252E);
  static const surfaceSelected = Color(0xFF182559);
  static const border = Color(0xFF3C414F);
  static const surfaceDisabled = Color(0xFF262831);

  // Content.
  static const contentPrimary = Color(0xFFF4F4F0);
  static const contentSecondary = Color(0xFFB8BAC2);
  static const contentDisabled = Color(0xFF8D909F);

  // Status.
  static const success = Color(0xFF4CD7A3);
  static const warning = Color(0xFFE4DC4A);
  static const destructive = Color(0xFFFF6B6B);

  /// Intended for artwork and scrims, not ordinary text or component states.
  static Color whiteA(double a) => Colors.white.withValues(alpha: a);
}

/// The six supported text roles.
///
/// Access these from [ThemeData.textTheme] so application typography follows
/// the active theme, for example `Theme.of(context).textTheme.epBody`.
extension EpTextTheme on TextTheme {
  TextStyle get epDisplay => displayLarge!;
  TextStyle get epPageHeading => headlineLarge!;
  TextStyle get epSectionHeading => titleLarge!;
  TextStyle get epBody => bodyMedium!;
  TextStyle get epLabel => labelLarge!;
  TextStyle get epCaption => bodySmall!;
}

/// Compatibility helper for existing call sites. Prefer one of the semantic
/// [EpTextTheme] roles for new and migrated UI.
TextStyle epText({
  double size = 13,
  FontWeight weight = FontWeight.w600,
  Color color = Ep.contentPrimary,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Archivo',
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Compatibility helper for existing display moments. Archivo Black is
/// reserved for brand and display text, never functional controls.
TextStyle epDisplay({
  double size = 18,
  Color color = Ep.contentPrimary,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Archivo Black',
    fontSize: size,
    color: color,
    letterSpacing: letterSpacing,
    height: height ?? 1.1,
  );
}

TextTheme _epTextTheme() {
  return const TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'Archivo Black',
      fontSize: 36,
      color: Ep.contentPrimary,
      height: 1.05,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: Ep.contentPrimary,
      height: 1.1,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: Ep.contentPrimary,
      height: 1.2,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Ep.contentPrimary,
      height: 1.45,
    ),
    labelLarge: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Ep.contentPrimary,
      letterSpacing: .4,
      height: 1.2,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Ep.contentSecondary,
      height: 1.35,
    ),
  );
}

WidgetStateProperty<Color?> _focusOverlay() =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return Ep.accent.withValues(alpha: .2);
      }
      if (states.contains(WidgetState.hovered)) {
        return Ep.contentPrimary.withValues(alpha: .08);
      }
      if (states.contains(WidgetState.pressed)) {
        return Ep.contentPrimary.withValues(alpha: .14);
      }
      return null;
    });

ThemeData buildEpTheme() {
  const scheme = ColorScheme.dark(
    primary: Ep.brand,
    onPrimary: Colors.white,
    secondary: Ep.accent,
    onSecondary: Ep.background,
    error: Ep.destructive,
    onError: Ep.background,
    surface: Ep.surface,
    onSurface: Ep.contentPrimary,
    surfaceContainerLowest: Ep.background,
    surfaceContainerLow: Ep.surface,
    surfaceContainer: Ep.surfaceRaised,
    surfaceContainerHigh: Ep.surfaceSelected,
    surfaceContainerHighest: Ep.surfaceDisabled,
    onSurfaceVariant: Ep.contentSecondary,
    outline: Ep.border,
    outlineVariant: Ep.border,
  );
  final textTheme = _epTextTheme();
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );

  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Ep.background,
    canvasColor: Ep.background,
    disabledColor: Ep.contentDisabled,
    focusColor: Ep.accent,
    colorScheme: scheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerTheme: const DividerThemeData(
      color: Ep.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: Ep.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape.copyWith(side: const BorderSide(color: Ep.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ep.surface,
      isDense: true,
      constraints: const BoxConstraints(minHeight: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: textTheme.epBody.copyWith(color: Ep.contentDisabled),
      labelStyle: textTheme.epLabel.copyWith(color: Ep.contentSecondary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Ep.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Ep.accent, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Ep.surfaceDisabled),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Ep.destructive),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Ep.destructive, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Ep.surfaceDisabled
              : Ep.brand,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Ep.contentDisabled
              : Colors.white,
        ),
        overlayColor: _focusOverlay(),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: WidgetStatePropertyAll(controlShape),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Ep.contentDisabled
              : Ep.accent,
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return const BorderSide(color: Ep.surfaceDisabled);
          }
          return BorderSide(
            color: states.contains(WidgetState.focused) ? Ep.accent : Ep.border,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          );
        }),
        overlayColor: _focusOverlay(),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: WidgetStatePropertyAll(controlShape),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Ep.contentDisabled
              : Ep.accent,
        ),
        overlayColor: _focusOverlay(),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: WidgetStatePropertyAll(controlShape),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? Ep.contentDisabled
              : Ep.contentPrimary,
        ),
        overlayColor: _focusOverlay(),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Ep.surface,
      selectedColor: Ep.surfaceSelected,
      disabledColor: Ep.surfaceDisabled,
      side: const BorderSide(color: Ep.border),
      shape: const StadiumBorder(),
      labelStyle: textTheme.epLabel.copyWith(color: Ep.contentSecondary),
      secondaryLabelStyle: textTheme.epLabel.copyWith(color: Ep.contentPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      showCheckmark: false,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Ep.contentPrimary,
      selectionColor: Ep.brand.withValues(alpha: .4),
      selectionHandleColor: Ep.brand,
    ),
  );
}
