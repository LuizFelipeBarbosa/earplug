import 'package:flutter/material.dart';

/// EarPlug's semantic design tokens.
///
/// Screens should choose a token for its purpose, rather than creating a
/// lighter or darker color with opacity. Artwork and readability overlays are
/// the intentional exceptions.
abstract final class Ep {
  // Core tokens.
  static const background = Color(0xFF0A0A0B);
  static const ink = Color(0xFFF2F2EF);
  static const muted = Color(0xFF9B98A4);
  static const accent = Color(0xFF8B5CFF);
  static const accentDeep = Color(0xFF6D3EF0);
  static const onAccent = Color(0xFF050506);
  static const panel = Color(0xFF141416);
  static const line = Color(0x24F2F2EF);
  static const outline = Color(0x4DFFFFFF);

  // Surfaces.
  static const surface = panel;
  static const surfaceRaised = Color(0xFF1C1C1F);
  static const surfaceSelected = Color(0xFF221B33);
  static const border = line;
  static const surfaceDisabled = Color(0xFF202024);
  static const tabBarBackground = background;

  // Content.
  static const contentPrimary = ink;
  static const contentSecondary = muted;
  static const contentDisabled = Color(0xFF6E6B78);

  // Status.
  static const success = Color(0xFF4CD7A3);
  static const warning = ink;
  static const destructive = Color(0xFFFF6B6B);
  static const successTint = Color(0xFF15352C);
  static const warningTint = panel;
  static const destructiveTint = Color(0xFF3B1C20);

  /// deprecated, use accent
  static const brand = accent;

  /// deprecated, use accent; the old volt-yellow is gone
  static const volt = accent;

  // Short semantic aliases retained for existing screens.
  static const mute = contentDisabled;
  static const raised = surfaceRaised;
  static const selected = surfaceSelected;
  static const dark = background;

  /// Intended for artwork and scrims, not ordinary text or component states.
  static Color whiteA(double a) => Colors.white.withValues(alpha: a);
}

/// Shared dimensions for page layouts and controls.
abstract final class EpLayout {
  static const desktopBreakpoint = 960.0;
  static const workspaceWidth = 1120.0;
  static const cardRadius = 0.0;
  static const controlRadius = 0.0;
  static const pillRadius = 999.0;
  static const gutter = 20.0;
  static const railWidth = 240.0;
  static const tabBarHeight = 64.0;
  static const fieldGap = 20.0;
  static const formSectionGap = 32.0;
  static const inputHeight = 48.0;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static bool stackActions(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 &&
      MediaQuery.textScalerOf(context).scale(1) > 1.3;
}

@immutable
class EpPalette extends ThemeExtension<EpPalette> {
  const EpPalette({
    required this.brand,
    required this.accent,
    required this.volt,
    required this.accentDeep,
    required this.onAccent,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSelected,
    required this.border,
    required this.outline,
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
    brand: Ep.accent,
    accent: Ep.accent,
    volt: Ep.accent,
    accentDeep: Ep.accentDeep,
    onAccent: Ep.onAccent,
    background: Ep.background,
    surface: Ep.surface,
    surfaceRaised: Ep.surfaceRaised,
    surfaceSelected: Ep.surfaceSelected,
    border: Ep.border,
    outline: Ep.outline,
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
    brand: Color(0xFF6D3EF0),
    accent: Color(0xFF6D3EF0),
    volt: Color(0xFF6D3EF0),
    accentDeep: Color(0xFF5A2FD6),
    onAccent: Color(0xFFFFFFFF),
    background: Color(0xFFF4F3F0),
    surface: Color(0xFFE9E8E4),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSelected: Color(0xFFE6DEFF),
    border: Color(0x240A0A0B),
    outline: Color(0x4D0A0A0B),
    surfaceDisabled: Color(0xFFDCDBD6),
    tabBarBackground: Color(0xFFF4F3F0),
    contentPrimary: Color(0xFF0A0A0B),
    contentSecondary: Color(0xFF5F5C69),
    contentDisabled: Color(0xFF8A8792),
    success: Color(0xFF087A5B),
    warning: Color(0xFF0A0A0B),
    destructive: Color(0xFFB4232D),
    successTint: Color(0xFFE0F3EC),
    warningTint: Color(0xFFE9E8E4),
    destructiveTint: Color(0xFFFAE6E8),
  );

  final Color brand;
  final Color accent;
  final Color volt;
  final Color accentDeep;
  final Color onAccent;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSelected;
  final Color border;
  final Color outline;
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
  Color get panel => surface;
  Color get line => border;
  Color get muted => contentSecondary;

  /// Highlight surfaces follow the active theme's accent token.
  Color get highlight => accent;

  /// Highlight content follows the foreground paired with the accent token.
  Color get onHighlight => onAccent;

  @override
  EpPalette copyWith({
    Color? brand,
    Color? accent,
    Color? volt,
    Color? accentDeep,
    Color? onAccent,
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSelected,
    Color? border,
    Color? outline,
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
    accentDeep: accentDeep ?? this.accentDeep,
    onAccent: onAccent ?? this.onAccent,
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceSelected: surfaceSelected ?? this.surfaceSelected,
    border: border ?? this.border,
    outline: outline ?? this.outline,
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
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      border: Color.lerp(border, other.border, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
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

/// Semantic text roles for shared interface components.
///
/// Access these from [ThemeData.textTheme] so application typography follows
/// the active theme, for example `Theme.of(context).textTheme.epBody`.
extension EpTextTheme on TextTheme {
  TextStyle get epDisplay => displayLarge!;
  TextStyle get epPageHeading => headlineLarge!;
  TextStyle get epPosterTitle => headlineMedium!;
  TextStyle get epSheetTitle => headlineSmall!;
  TextStyle get epSectionHeading => titleLarge!;
  TextStyle get epSection => titleMedium!;
  TextStyle get epBody => bodyMedium!;
  TextStyle get epInput => bodyLarge!;
  TextStyle get epLabel => labelLarge!;
  TextStyle get epChipLabel => labelMedium!;
  TextStyle get epMeta => labelSmall!;
  TextStyle get epCaption => bodySmall!;

  TextStyle epDisplayAt(double size) =>
      epDisplay.copyWith(fontSize: size, letterSpacing: -size * .01);
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
    fontFamily: 'PP Telegraf',
    fontSize: size,
    fontWeight: weight.value >= FontWeight.w700.value
        ? FontWeight.w800
        : FontWeight.w400,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Compatibility helper for existing display moments using PP Telegraf
/// Ultrabold with the display role's tight spacing and line height.
TextStyle epDisplay({
  double size = 18,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'PP Telegraf',
    fontSize: size,
    fontWeight: FontWeight.w800,
    color: color,
    letterSpacing: letterSpacing ?? -size * .01,
    height: height ?? .88,
  );
}

TextTheme _epTextTheme(EpPalette palette) {
  return TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'PP Telegraf',
      fontWeight: FontWeight.w800,
      fontSize: 44,
      color: palette.contentPrimary,
      height: .88,
      letterSpacing: -.44,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'PP Telegraf',
      fontSize: 36,
      fontWeight: FontWeight.w800,
      color: palette.contentPrimary,
      height: .9,
      letterSpacing: -.36,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'PP Telegraf',
      fontWeight: FontWeight.w800,
      fontSize: 30,
      color: palette.contentPrimary,
      height: .9,
      letterSpacing: -.3,
    ),
    headlineSmall: TextStyle(
      fontFamily: 'PP Telegraf',
      fontSize: 24,
      fontWeight: FontWeight.w800,
      color: palette.contentPrimary,
      height: 1.0,
      letterSpacing: -.24,
    ),
    titleLarge: TextStyle(
      fontFamily: 'PP Telegraf',
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: palette.contentPrimary,
      height: 1.1,
      letterSpacing: -.2,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Azeret Mono',
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: palette.contentSecondary,
      letterSpacing: 1.54,
      height: 1.3,
    ),
    bodyLarge: TextStyle(
      fontFamily: 'PP Telegraf',
      fontSize: 18,
      fontWeight: FontWeight.w400,
      color: palette.contentPrimary,
      height: 1.4,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'PP Telegraf',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: palette.contentPrimary,
      height: 1.45,
    ),
    labelLarge: TextStyle(
      fontFamily: 'Azeret Mono',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: palette.contentPrimary,
      letterSpacing: 1.68,
      height: 1.2,
    ),
    labelMedium: TextStyle(
      fontFamily: 'Azeret Mono',
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: palette.contentPrimary,
      letterSpacing: 1.54,
      height: 1.2,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Azeret Mono',
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: palette.contentSecondary,
      height: 1.35,
      letterSpacing: 1.54,
    ),
    bodySmall: TextStyle(
      fontFamily: 'PP Telegraf',
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: palette.contentSecondary,
      height: 1.45,
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
    primary: palette.accent,
    onPrimary: palette.onAccent,
    secondary: palette.accentDeep,
    onSecondary: palette.onAccent,
    error: palette.destructive,
    onError: brightness == Brightness.dark ? palette.background : Colors.white,
    surface: palette.background,
    onSurface: palette.contentPrimary,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surfaceRaised,
    surfaceContainerHigh: palette.surfaceSelected,
    surfaceContainerHighest: palette.surfaceDisabled,
    onSurfaceVariant: palette.contentSecondary,
    outline: palette.border,
    outlineVariant: palette.outline,
  );
  final textTheme = _epTextTheme(palette);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(EpLayout.cardRadius),
  );
  const pillShape = StadiumBorder();
  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(EpLayout.controlRadius),
  );

  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    fontFamily: 'PP Telegraf',
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
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.contentPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.epSectionHeading,
      centerTitle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape.copyWith(side: BorderSide(color: palette.border)),
      titleTextStyle: textTheme.epSectionHeading,
      contentTextStyle: textTheme.epBody,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surface,
      contentTextStyle: textTheme.epBody,
      actionTextColor: palette.accent,
      behavior: SnackBarBehavior.floating,
      shape: shape.copyWith(side: BorderSide(color: palette.border)),
      elevation: 0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.surfaceSelected
              : palette.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : states.contains(WidgetState.selected)
              ? palette.accent
              : palette.contentSecondary,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: palette.border)),
        shape: WidgetStatePropertyAll(controlShape),
        overlayColor: _focusOverlay(palette),
      ),
    ),
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
      shape: shape.copyWith(side: BorderSide.none),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      isDense: true,
      constraints: const BoxConstraints(minHeight: EpLayout.inputHeight),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      hintStyle: textTheme.epInput.copyWith(color: palette.contentSecondary),
      labelStyle: textTheme.epSection.copyWith(color: palette.contentSecondary),
      alignLabelWithHint: true,
      errorMaxLines: 3,
      helperMaxLines: 3,
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.contentPrimary, width: 1),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      disabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.outline, width: 1),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.destructive, width: 1),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: palette.destructive, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.surfaceDisabled
              : palette.accent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : palette.onAccent,
        ),
        overlayColor: _focusOverlay(palette),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: const WidgetStatePropertyAll(pillShape),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : palette.contentPrimary,
        ),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(color: palette.surfaceDisabled);
          }
          return BorderSide(
            color: states.contains(WidgetState.focused)
                ? palette.accent
                : palette.outline,
            width: states.contains(WidgetState.focused) ? 1.5 : 1,
          );
        }),
        overlayColor: _focusOverlay(palette),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: const WidgetStatePropertyAll(pillShape),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : palette.contentPrimary,
        ),
        overlayColor: _focusOverlay(palette),
        textStyle: WidgetStatePropertyAll(textTheme.epLabel),
        shape: WidgetStatePropertyAll(controlShape),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? palette.contentDisabled
              : palette.contentPrimary,
        ),
        overlayColor: _focusOverlay(palette),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: palette.contentPrimary,
      disabledColor: palette.surfaceDisabled,
      side: BorderSide(color: palette.outline),
      shape: const StadiumBorder(),
      labelStyle: textTheme.epChipLabel.copyWith(
        color: palette.contentSecondary,
      ),
      secondaryLabelStyle: textTheme.epChipLabel.copyWith(
        color: palette.onAccent,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      showCheckmark: false,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.contentPrimary,
      selectionColor: palette.accent.withValues(alpha: .4),
      selectionHandleColor: palette.accent,
    ),
  );
}
