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
  static const volt = Color(0xFFE4DC4A);

  // Surfaces.
  static const background = Color(0xFF0A0A0C);
  static const surface = Color(0xFF131418);
  static const surfaceRaised = Color(0xFF1C1E26);
  static const surfaceSelected = Color(0xFF1B2A6B);
  static const border = Color(0xFF2E323E);
  static const surfaceDisabled = Color(0xFF262831);
  static const tabBarBackground = Color(0xFF0A0A0C);

  // Content.
  static const contentPrimary = Color(0xFFF4F4F0);
  static const contentSecondary = Color(0xFFB8BAC2);
  // Lifted slightly from the board's muted swatch so it remains AA on the
  // selected surface, where disabled and secondary states can both appear.
  static const contentDisabled = Color(0xFF9A9CA8);

  // Status.
  static const success = Color(0xFF4CD7A3);
  static const warning = volt;
  static const destructive = Color(0xFFFF6B6B);
  static const successTint = Color(0xFF15352C);
  static const warningTint = Color(0xFF393717);
  static const destructiveTint = Color(0xFF3B1C20);

  // Short semantic aliases used by the refresh component grammar. Existing
  // names remain the source of truth for compatibility with current screens.
  static const ink = contentPrimary;
  static const mute = contentDisabled;
  static const raised = surfaceRaised;
  static const selected = surfaceSelected;
  static const dark = background;

  /// Intended for artwork and scrims, not ordinary text or component states.
  static Color whiteA(double a) => Colors.white.withValues(alpha: a);
}

@immutable
class EpPalette extends ThemeExtension<EpPalette> {
  const EpPalette({
    required this.brand,
    required this.accent,
    required this.volt,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSelected,
    required this.border,
    required this.surfaceDisabled,
    required this.tabBarBackground,
    required this.contentPrimary,
    required this.contentSecondary,
    required this.contentDisabled,
    required this.success,
    required this.warning,
    required this.destructive,
    required this.successTint,
    required this.warningTint,
    required this.destructiveTint,
  });

  static const darkMode = EpPalette(
    brand: Ep.brand,
    accent: Ep.accent,
    volt: Ep.volt,
    background: Ep.background,
    surface: Ep.surface,
    surfaceRaised: Ep.surfaceRaised,
    surfaceSelected: Ep.surfaceSelected,
    border: Ep.border,
    surfaceDisabled: Ep.surfaceDisabled,
    tabBarBackground: Ep.tabBarBackground,
    contentPrimary: Ep.contentPrimary,
    contentSecondary: Ep.contentSecondary,
    contentDisabled: Ep.contentDisabled,
    success: Ep.success,
    warning: Ep.warning,
    destructive: Ep.destructive,
    successTint: Ep.successTint,
    warningTint: Ep.warningTint,
    destructiveTint: Ep.destructiveTint,
  );

  static const lightMode = EpPalette(
    brand: Color(0xFF1435F0),
    accent: Color(0xFF1435F0),
    volt: Color(0xFF6F6500),
    background: Color(0xFFF6F5F1),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFCFCFA),
    surfaceSelected: Color(0xFFE7EBFF),
    border: Color(0xFFCDD1DA),
    surfaceDisabled: Color(0xFFE5E7EC),
    tabBarBackground: Color(0xFFFFFFFF),
    contentPrimary: Color(0xFF16171C),
    contentSecondary: Color(0xFF525761),
    contentDisabled: Color(0xFF5E6470),
    success: Color(0xFF087A5B),
    warning: Color(0xFF6F6500),
    destructive: Color(0xFFB4232D),
    successTint: Color(0xFFE0F3EC),
    warningTint: Color(0xFFF3EFCB),
    destructiveTint: Color(0xFFFAE6E8),
  );

  final Color brand;
  final Color accent;
  final Color volt;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSelected;
  final Color border;
  final Color surfaceDisabled;
  final Color tabBarBackground;
  final Color contentPrimary;
  final Color contentSecondary;
  final Color contentDisabled;
  final Color success;
  final Color warning;
  final Color destructive;
  final Color successTint;
  final Color warningTint;
  final Color destructiveTint;

  Color get ink => contentPrimary;
  Color get mute => contentDisabled;
  Color get raised => surfaceRaised;
  Color get selected => surfaceSelected;
  Color get dark => background;

  @override
  EpPalette copyWith({
    Color? brand,
    Color? accent,
    Color? volt,
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSelected,
    Color? border,
    Color? surfaceDisabled,
    Color? tabBarBackground,
    Color? contentPrimary,
    Color? contentSecondary,
    Color? contentDisabled,
    Color? success,
    Color? warning,
    Color? destructive,
    Color? successTint,
    Color? warningTint,
    Color? destructiveTint,
  }) => EpPalette(
    brand: brand ?? this.brand,
    accent: accent ?? this.accent,
    volt: volt ?? this.volt,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceSelected: surfaceSelected ?? this.surfaceSelected,
    border: border ?? this.border,
    surfaceDisabled: surfaceDisabled ?? this.surfaceDisabled,
    tabBarBackground: tabBarBackground ?? this.tabBarBackground,
    contentPrimary: contentPrimary ?? this.contentPrimary,
    contentSecondary: contentSecondary ?? this.contentSecondary,
    contentDisabled: contentDisabled ?? this.contentDisabled,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    destructive: destructive ?? this.destructive,
    successTint: successTint ?? this.successTint,
    warningTint: warningTint ?? this.warningTint,
    destructiveTint: destructiveTint ?? this.destructiveTint,
  );

  @override
  EpPalette lerp(covariant EpPalette? other, double t) {
    if (other == null) return this;
    return EpPalette(
      brand: Color.lerp(brand, other.brand, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      volt: Color.lerp(volt, other.volt, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceDisabled: Color.lerp(surfaceDisabled, other.surfaceDisabled, t)!,
      tabBarBackground: Color.lerp(
        tabBarBackground,
        other.tabBarBackground,
        t,
      )!,
      contentPrimary: Color.lerp(contentPrimary, other.contentPrimary, t)!,
      contentSecondary: Color.lerp(
        contentSecondary,
        other.contentSecondary,
        t,
      )!,
      contentDisabled: Color.lerp(contentDisabled, other.contentDisabled, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      warningTint: Color.lerp(warningTint, other.warningTint, t)!,
      destructiveTint: Color.lerp(destructiveTint, other.destructiveTint, t)!,
    );
  }
}

extension EpBuildContext on BuildContext {
  EpPalette get epColors => Theme.of(this).extension<EpPalette>()!;
}

/// The six supported text roles.
///
/// Access these from [ThemeData.textTheme] so application typography follows
/// the active theme, for example `Theme.of(context).textTheme.epBody`.
extension EpTextTheme on TextTheme {
  TextStyle get epDisplay => displayLarge!;
  TextStyle get epPageHeading => headlineLarge!;
  TextStyle get epPosterTitle => headlineMedium!;
  TextStyle get epSectionHeading => titleLarge!;
  TextStyle get epSection => titleMedium!;
  TextStyle get epBody => bodyMedium!;
  TextStyle get epLabel => labelLarge!;
  TextStyle get epChipLabel => labelMedium!;
  TextStyle get epMeta => labelSmall!;
  TextStyle get epCaption => bodySmall!;
}

/// Compatibility helper for existing call sites. Prefer one of the semantic
/// [EpTextTheme] roles for new and migrated UI.
TextStyle epText({
  double size = 13,
  FontWeight weight = FontWeight.w600,
  Color? color,
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
  Color? color,
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

TextTheme _epTextTheme(EpPalette palette) {
  return TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'Archivo Black',
      fontSize: 36,
      color: palette.contentPrimary,
      height: 1.05,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: palette.contentPrimary,
      height: 1.1,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Archivo Black',
      fontSize: 22,
      color: palette.contentPrimary,
      height: 1.18,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 17,
      fontWeight: FontWeight.w800,
      color: palette.contentPrimary,
      height: 1.2,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: palette.contentPrimary,
      letterSpacing: 2,
      height: 1.2,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: palette.contentPrimary,
      height: 1.45,
    ),
    labelLarge: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: palette.contentPrimary,
      letterSpacing: .4,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: palette.contentPrimary,
      letterSpacing: .8,
      height: 1.2,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: palette.contentSecondary,
      height: 1.35,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Archivo',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: palette.contentSecondary,
      height: 1.35,
    ),
  );
}

WidgetStateProperty<Color?> _focusOverlay(EpPalette palette) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return palette.accent.withValues(alpha: .2);
      }
      if (states.contains(WidgetState.hovered)) {
        return palette.contentPrimary.withValues(alpha: .08);
      }
      if (states.contains(WidgetState.pressed)) {
        return palette.contentPrimary.withValues(alpha: .14);
      }
      return null;
    });

ThemeData buildEpTheme([Brightness brightness = Brightness.dark]) {
  final palette = brightness == Brightness.dark
      ? EpPalette.darkMode
      : EpPalette.lightMode;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.brand,
    onPrimary: Colors.white,
    secondary: palette.accent,
    onSecondary: palette.background,
    error: palette.destructive,
    onError: brightness == Brightness.dark ? palette.background : Colors.white,
    surface: palette.surface,
    onSurface: palette.contentPrimary,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surfaceRaised,
    surfaceContainerHigh: palette.surfaceSelected,
    surfaceContainerHighest: palette.surfaceDisabled,
    onSurfaceVariant: palette.contentSecondary,
    outline: palette.border,
    outlineVariant: palette.border,
  );
  final textTheme = _epTextTheme(palette);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );

  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'Archivo',
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    disabledColor: palette.contentDisabled,
    focusColor: palette.accent,
    colorScheme: scheme,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [palette],
    dividerTheme: DividerThemeData(
      color: palette.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: shape.copyWith(side: BorderSide(color: palette.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      isDense: true,
      constraints: const BoxConstraints(minHeight: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: textTheme.epBody.copyWith(color: palette.contentDisabled),
      labelStyle: textTheme.epLabel.copyWith(color: palette.contentSecondary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: palette.accent, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: palette.surfaceDisabled),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: palette.destructive),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: palette.destructive, width: 2),
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
              ? palette.surfaceDisabled
              : palette.brand,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : Colors.white,
        ),
        overlayColor: _focusOverlay(palette),
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
              ? palette.contentDisabled
              : palette.accent,
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: palette.surfaceDisabled);
          }
          return BorderSide(
            color: states.contains(WidgetState.focused)
                ? palette.accent
                : palette.border,
            width: states.contains(WidgetState.focused) ? 2 : 1,
          );
        }),
        overlayColor: _focusOverlay(palette),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: WidgetStatePropertyAll(controlShape),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : palette.accent,
        ),
        overlayColor: _focusOverlay(palette),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: WidgetStatePropertyAll(controlShape),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : palette.contentPrimary,
        ),
        overlayColor: _focusOverlay(palette),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surface,
      selectedColor: palette.surfaceSelected,
      disabledColor: palette.surfaceDisabled,
      side: BorderSide(color: palette.border),
      shape: const StadiumBorder(),
      labelStyle: textTheme.epLabel.copyWith(color: palette.contentSecondary),
      secondaryLabelStyle: textTheme.epLabel.copyWith(
        color: palette.contentPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      showCheckmark: false,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.contentPrimary,
      selectionColor: palette.brand.withValues(alpha: .4),
      selectionHandleColor: palette.brand,
    ),
  );
}
