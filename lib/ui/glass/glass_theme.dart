import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'glass_tokens.dart';

/// Theme extension carrying the Liquid Glass palette and material parameters.
///
/// Pages and shared widgets read it through [GlassTheme.of]. When a widget is
/// pumped under a plain `MaterialApp`/`ThemeData` (widget tests, isolated
/// previews) the accessor falls back to the light palette instead of failing.
@immutable
class GlassThemeData extends ThemeExtension<GlassThemeData> {
  const GlassThemeData({required this.palette});

  final GlassPalette palette;

  static const GlassThemeData light = GlassThemeData(
    palette: GlassPalette.light,
  );
  static const GlassThemeData dark = GlassThemeData(palette: GlassPalette.dark);

  @override
  GlassThemeData copyWith({GlassPalette? palette}) =>
      GlassThemeData(palette: palette ?? this.palette);

  @override
  GlassThemeData lerp(ThemeExtension<GlassThemeData>? other, double t) {
    if (other is! GlassThemeData) return this;
    return t < 0.5 ? this : other;
  }
}

/// Convenience accessors for the glass design system.
extension GlassThemeContext on BuildContext {
  GlassThemeData get glassTheme =>
      Theme.of(this).extension<GlassThemeData>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? GlassThemeData.dark
          : GlassThemeData.light);

  GlassPalette get glass => glassTheme.palette;

  bool get isDarkGlass => glass.isDark;
}

/// Builds the application theme used by every screen.
ThemeData buildGlassTheme(Brightness brightness) {
  final GlassPalette palette = GlassPalette.of(brightness);
  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    primary: palette.tint,
    onPrimary: Colors.white,
    primaryContainer: palette.tint.withValues(alpha: 0.16),
    onPrimaryContainer: palette.tint,
    secondary: palette.indigo,
    onSecondary: Colors.white,
    secondaryContainer: palette.indigo.withValues(alpha: 0.16),
    onSecondaryContainer: palette.indigo,
    tertiary: palette.purple,
    onTertiary: Colors.white,
    error: palette.red,
    onError: Colors.white,
    errorContainer: palette.red.withValues(alpha: 0.14),
    onErrorContainer: palette.red,
    surface: palette.elevatedBackground,
    onSurface: palette.label,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.elevatedBackground,
    surfaceContainer: palette.tertiaryGroupedBackground,
    surfaceContainerHigh: palette.tertiaryGroupedBackground,
    surfaceContainerHighest: palette.fill,
    onSurfaceVariant: palette.secondaryLabel,
    outline: palette.separator,
    outlineVariant: palette.separator,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: palette.label,
    onInverseSurface: palette.groupedBackground,
    inversePrimary: palette.tint,
  );

  final TextTheme text = GlassType.textTheme(palette.label);
  final BorderRadius controlRadius = BorderRadius.circular(
    GlassRadii.control,
  );
  final ShapeBorder alertShape = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(GlassRadii.alert),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.groupedBackground,
    canvasColor: palette.groupedBackground,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: palette.fill.withValues(alpha: 0.4),
    dividerColor: palette.separator,
    textTheme: text,
    primaryTextTheme: text,
    iconTheme: IconThemeData(color: palette.label, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.label,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: GlassType.headline.copyWith(color: palette.label),
    ),
    dividerTheme: DividerThemeData(
      color: palette.separator,
      thickness: 0.5,
      space: 0.5,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: palette.tint,
      textColor: palette.label,
      subtitleTextStyle: GlassType.footnote.copyWith(
        color: palette.secondaryLabel,
      ),
      titleTextStyle: GlassType.body.copyWith(color: palette.label),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: GlassSpacing.lg,
        vertical: GlassSpacing.xs,
      ),
      minVerticalPadding: GlassSpacing.md,
      minLeadingWidth: 23,
      horizontalTitleGap: GlassSpacing.md,
      shape: const RoundedRectangleBorder(),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.fill,
      selectedColor: palette.isDark
          ? const Color(0xFF636366)
          : palette.elevatedBackground,
      disabledColor: palette.tertiaryFill,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(
        horizontal: GlassSpacing.md,
        vertical: GlassSpacing.sm,
      ),
      labelStyle: GlassType.subheadline.copyWith(color: palette.label),
      secondaryLabelStyle: GlassType.subheadline.copyWith(
        color: palette.label,
        fontWeight: FontWeight.w600,
      ),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.fill,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: GlassSpacing.lg,
        vertical: GlassSpacing.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: palette.tint, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: palette.red, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: controlRadius,
        borderSide: BorderSide(color: palette.red, width: 1.4),
      ),
      labelStyle: GlassType.body.copyWith(color: palette.secondaryLabel),
      floatingLabelStyle: GlassType.footnote.copyWith(color: palette.tint),
      hintStyle: GlassType.body.copyWith(color: palette.placeholder),
      helperStyle: GlassType.caption1.copyWith(color: palette.secondaryLabel),
      errorStyle: GlassType.caption1.copyWith(color: palette.red),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: palette.tint,
      inactiveTrackColor: palette.fill,
      disabledActiveTrackColor: palette.tint.withValues(alpha: 0.35),
      disabledInactiveTrackColor: palette.tertiaryFill,
      thumbColor: Colors.white,
      overlayColor: palette.tint.withValues(alpha: 0.14),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      thumbShape: const RoundSliderThumbShape(
        enabledThumbRadius: 10,
        elevation: 2,
        pressedElevation: 4,
      ),
      trackShape: const RoundedRectSliderTrackShape(),
      valueIndicatorColor: palette.elevatedBackground,
      valueIndicatorTextStyle: GlassType.caption1.copyWith(
        color: palette.label,
      ),
      showValueIndicator: ShowValueIndicator.never,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        if (states.contains(WidgetState.selected)) return palette.green;
        return palette.fill;
      }),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(
        Colors.transparent,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.elevatedBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: alertShape,
      titleTextStyle: GlassType.headline.copyWith(color: palette.label),
      contentTextStyle: GlassType.body.copyWith(color: palette.label),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.elevatedBackground,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: palette.elevatedBackground,
      elevation: 0,
      shape: RoundedSuperellipseBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(GlassRadii.sheet),
        ),
      ),
      dragHandleColor: palette.tertiaryLabel,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.elevatedBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(GlassRadii.control + 2),
      ),
      textStyle: GlassType.body.copyWith(color: palette.label),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.isDark
          ? const Color(0xF22C2C2E)
          : const Color(0xF21C1C1E),
      contentTextStyle: GlassType.subheadline.copyWith(color: Colors.white),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(GlassRadii.control + 2),
      ),
      elevation: 0,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.tint,
      linearTrackColor: palette.fill,
      circularTrackColor: palette.fill,
      linearMinHeight: 3,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.tint,
        textStyle: GlassType.body.copyWith(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
          horizontal: GlassSpacing.md,
          vertical: GlassSpacing.sm,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.tint,
        foregroundColor: Colors.white,
        textStyle: GlassType.body.copyWith(fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(horizontal: GlassSpacing.xl),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.tint,
        side: BorderSide(color: palette.tint.withValues(alpha: 0.4)),
        textStyle: GlassType.body.copyWith(fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 50),
        shape: const StadiumBorder(),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      side: BorderSide(color: palette.tertiaryLabel, width: 1.2),
      fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected)
            ? palette.tint
            : Colors.transparent;
      }),
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: <ThemeExtension<dynamic>>[
      GlassThemeData(palette: palette),
    ],
  );
}
